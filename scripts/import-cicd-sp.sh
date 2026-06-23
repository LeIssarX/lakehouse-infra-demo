#!/usr/bin/env bash
# ==========================================================
# Adopt the pre-registered CI/CD service principal into the OpenTofu state
# ==========================================================
# bootstrap-cicd.sh pre-registers the SP in the Databricks account (to grant it
# account_admin), so a fresh `tofu apply` otherwise fails with
#   "cannot create service principal: User ... already exists in this account".
# This idempotently imports databricks_service_principal.cicd[0] before apply.
#
# Used by scripts/tofu-wrapper.sh (local) AND the CI deploy workflows.
# No-op when: no cicd_sp_application_id / databricks_account_id, the SP isn't
# registered yet, no Databricks token obtainable, or it's already in state.
# Auth: the deploying SP's client creds (ARM_CLIENT_ID/SECRET/TENANT_ID), else az.
#
# Usage: scripts/import-cicd-sp.sh <dev|prod>
# Must run after `tofu init` (needs the backend) — run it from anywhere.
# ==========================================================

set -euo pipefail

ENV="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/.." && pwd))"
cd "$REPO_ROOT/infra"

DB_RESOURCE="2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"  # Azure Databricks programmatic id

app_id=$(grep -hE '^[[:space:]]*cicd_sp_application_id[[:space:]]*=' "envs/$ENV"/*.tfvars 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
acct=$(grep -hE '^[[:space:]]*databricks_account_id[[:space:]]*=' common.tfvars 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
if [[ -z "$app_id" || "$app_id" == "null" || -z "$acct" ]]; then
  echo "[import-cicd-sp] no cicd_sp_application_id / databricks_account_id — skipping"; exit 0
fi

if tofu state list 2>/dev/null | grep -qxF 'databricks_service_principal.cicd[0]'; then
  echo "[import-cicd-sp] already in state — skipping"; exit 0
fi

# Databricks account token: prefer the SP's own client credentials, else az.
token=""
if [[ -n "${ARM_CLIENT_ID:-}" && -n "${ARM_CLIENT_SECRET:-}" && -n "${ARM_TENANT_ID:-}" ]]; then
  token=$(curl -sf -X POST "https://login.microsoftonline.com/${ARM_TENANT_ID}/oauth2/v2.0/token" \
    -d "grant_type=client_credentials&client_id=${ARM_CLIENT_ID}&client_secret=${ARM_CLIENT_SECRET}&scope=${DB_RESOURCE}/.default" \
    2>/dev/null | jq -r '.access_token // empty' 2>/dev/null || echo "")
fi
if [[ -z "$token" ]] && command -v az >/dev/null 2>&1; then
  token=$(az account get-access-token --resource "$DB_RESOURCE" --query accessToken -o tsv 2>/dev/null || echo "")
fi
if [[ -z "$token" ]]; then
  echo "[import-cicd-sp] no Databricks token — skipping (apply may report 'already exists')"; exit 0
fi

# SCIM v2 endpoint — the bare /servicePrincipals path 303-redirects to nothing.
num_id=$(curl -sf -H "Authorization: Bearer $token" \
  "https://accounts.azuredatabricks.net/api/2.0/accounts/${acct}/scim/v2/ServicePrincipals?filter=applicationId%20eq%20%22${app_id}%22" 2>/dev/null \
  | jq -r '.Resources[0].id // empty' 2>/dev/null || echo "")
if [[ -z "$num_id" ]]; then
  echo "[import-cicd-sp] SP not yet registered in the account — nothing to import"; exit 0
fi

var_files=(-var-file=common.tfvars)
for f in "envs/$ENV"/*.tfvars; do
  [[ -e "$f" ]] && var_files+=("-var-file=$f")
done

# On greenfield deploys the Databricks workspace doesn't exist yet. tofu import
# reads ALL data sources — including data.databricks_current_metastore.auto which
# calls the workspace endpoint — before the workspace is provisioned. Detect this
# and override unity_catalog_metastore_mode for the import only, suppressing the
# workspace-level data source so the account-level SP import can succeed.
extra_import_vars=()
ws_name=$(grep -hE '^[[:space:]]*databricks_workspace_name[[:space:]]*=' "envs/$ENV"/*.tfvars 2>/dev/null \
  | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
rg_name=$(grep -hE '^[[:space:]]*resource_group_name[[:space:]]*=' "envs/$ENV"/*.tfvars 2>/dev/null \
  | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
if [[ -n "$ws_name" && -n "$rg_name" ]]; then
  sub_id="${ARM_SUBSCRIPTION_ID:-$(az account show --query id -o tsv 2>/dev/null || echo "")}"
  if [[ -n "$sub_id" ]] && ! az resource show \
      --ids "/subscriptions/${sub_id}/resourceGroups/${rg_name}/providers/Microsoft.Databricks/workspaces/${ws_name}" \
      >/dev/null 2>&1; then
    echo "[import-cicd-sp] workspace not yet provisioned — suppressing workspace data sources for import"
    extra_import_vars=(-var 'unity_catalog_metastore_mode=existing' -var 'unity_catalog_metastore_id=00000000-0000-0000-0000-000000000000')
  fi
fi

echo "[import-cicd-sp] importing databricks_service_principal.cicd[0] = $num_id"
if tofu import "${var_files[@]}" "${extra_import_vars[@]}" 'databricks_service_principal.cicd[0]' "$num_id"; then
  echo "✅ Imported databricks_service_principal.cicd[0]"
else
  echo "⚠️  Auto-import failed — apply may report 'already exists'; import manually if so."
fi
