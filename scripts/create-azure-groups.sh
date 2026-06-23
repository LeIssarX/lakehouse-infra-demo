#!/usr/bin/env bash
# ==========================================================
# Create Azure AD Security Groups for Databricks AIM
# ==========================================================
# Creates the standard Databricks security groups using the
# currently logged-in Azure user's credentials. Regular users
# can create security groups in most Azure AD tenants — no
# Global Admin or Group.ReadWrite.All application permission
# required.
#
# This is the RECOMMENDED approach: pre-create the groups here
# (as the logged-in user), then Terraform references them by
# object_id via aim_group_ids in identity.tfvars. The CI/CD
# service principal never needs Group.ReadWrite.All.
#
# The wizard embeds the IDs automatically when you click Save.
#
# Usage: scripts/create-azure-groups.sh <dev|prod>
#
# Env vars (set by wizard):
#   WIZARD_AIM_GROUPS_JSON  JSON {"key": {"display_name": "..."}, ...}
#                           Passes the exact group names configured
#                           in the wizard. Falls back to defaults.
#   PROJECT_SLUG            Project slug (informational only).
# ==========================================================

set -euo pipefail

ENV="${1:-}"

if [[ -z "$ENV" ]]; then
  echo "❌ Error: Environment parameter required"
  echo "Usage: $0 <dev|prod>"
  exit 1
fi

if [[ ! "$ENV" =~ ^(dev|prod)$ ]]; then
  echo "❌ Error: Environment must be 'dev' or 'prod'"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/.." && pwd))"

# ---------------------------------------------------------------------------
# Colour logging
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log_step()    { echo -e "\n${CYAN}==> $*${NC}"; }
log_info()    { echo -e "${GREEN}[INFO]${NC}    $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*" >&2; }

# Capitalise first letter (bash-portable, no bash 4 required)
ENV_SUFFIX="$(echo "${ENV:0:1}" | tr '[:lower:]' '[:upper:]')${ENV:1}"

# ---------------------------------------------------------------------------
# Step 1: Resolve group names
# ---------------------------------------------------------------------------
log_step "Step 1: Resolving group definitions for ${ENV_SUFFIX}"

# Canonical key order — mirrors services/models.py default_aim_groups()
GROUP_KEYS=(admins engineers analysts stewards users)
declare -A GROUP_NAMES

if [[ -n "${WIZARD_AIM_GROUPS_JSON:-}" ]]; then
  # Wizard passed the configured group names — use them exactly.
  log_info "Using group names from wizard state (WIZARD_AIM_GROUPS_JSON)"
  while IFS=$'\t' read -r key name; do
    [[ -n "$key" ]] && GROUP_NAMES["$key"]="$name"
  done < <(python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    for k, v in d.items():
        print('{}\t{}'.format(k, v.get('display_name', k)))
except Exception:
    pass
" <<< "$WIZARD_AIM_GROUPS_JSON" 2>/dev/null || true)
fi

# Fill in any missing keys with defaults matching the wizard's default_aim_groups()
[[ -z "${GROUP_NAMES[admins]+x}"    ]] && GROUP_NAMES[admins]="Databricks-Admins-${ENV_SUFFIX}"
[[ -z "${GROUP_NAMES[engineers]+x}" ]] && GROUP_NAMES[engineers]="Databricks-Engineers-${ENV_SUFFIX}"
[[ -z "${GROUP_NAMES[analysts]+x}"  ]] && GROUP_NAMES[analysts]="Databricks-Analysts-${ENV_SUFFIX}"
[[ -z "${GROUP_NAMES[stewards]+x}"  ]] && GROUP_NAMES[stewards]="Databricks-Stewards-${ENV_SUFFIX}"
[[ -z "${GROUP_NAMES[users]+x}"     ]] && GROUP_NAMES[users]="Databricks-Users-${ENV_SUFFIX}"

for key in "${GROUP_KEYS[@]}"; do
  log_info "  ${key} → ${GROUP_NAMES[$key]}"
done

# ---------------------------------------------------------------------------
# Step 2: Verify Azure CLI login
# ---------------------------------------------------------------------------
log_step "Step 2: Verifying Azure CLI authentication"
if ! az account show >/dev/null 2>&1; then
  log_error "Not logged in to Azure CLI. Run 'az login' first."
  exit 1
fi
CURRENT_USER="$(az account show --query 'user.name' -o tsv 2>/dev/null || echo '(unknown)')"
log_info "Authenticated as: $CURRENT_USER"

# ---------------------------------------------------------------------------
# Step 3: Create groups (idempotent)
# ---------------------------------------------------------------------------
log_step "Step 3: Creating Azure AD security groups"

declare -A ID_MAP

for key in "${GROUP_KEYS[@]}"; do
  display_name="${GROUP_NAMES[$key]}"
  mail_nick="$(echo "$display_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')"

  log_info "Creating group: $display_name"

  # Idempotent: get the existing group ID if it exists
  existing_id="$(az ad group list \
    --filter "displayName eq '${display_name}'" \
    --query '[0].id' -o tsv 2>/dev/null || echo "")"

  if [[ -n "$existing_id" && "$existing_id" != "None" && "$existing_id" != "null" ]]; then
    log_warn "$display_name already exists (ID: $existing_id)"
    ID_MAP["$key"]="$existing_id"
  else
    new_id="$(az ad group create \
      --display-name "$display_name" \
      --mail-nickname "$mail_nick" \
      --query id -o tsv 2>/dev/null || echo "")"

    if [[ -n "$new_id" ]]; then
      log_success "✅ Created: $display_name (ID: $new_id)"
      ID_MAP["$key"]="$new_id"
    else
      log_error "Failed to create group: $display_name"
      log_error "Check that your account has permission to create security groups in this tenant."
      log_error "If group creation is restricted by policy, contact your Azure AD administrator."
      exit 1
    fi
  fi
done

# ---------------------------------------------------------------------------
# Step 4: Write .aim-group-ids.json into the repo
# ---------------------------------------------------------------------------
# The wizard reads this file when you click Save and embeds the IDs into
# infra/envs/${ENV}/identity.tfvars as aim_group_ids = { ... }.
# Terraform then uses the IDs directly — no Group.ReadWrite.All needed.
log_step "Step 4: Writing group IDs to infra/envs/${ENV}/.aim-group-ids.json"

OUTPUT_DIR="$REPO_ROOT/infra/envs/$ENV"
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/.aim-group-ids.json"

{
  printf '{\n'
  first=true
  for key in "${GROUP_KEYS[@]}"; do
    [[ -n "${ID_MAP[$key]+x}" ]] || continue
    [[ "$first" == "true" ]] && first=false || printf ',\n'
    printf '  "%s": "%s"' "$key" "${ID_MAP[$key]}"
  done
  printf '\n}\n'
} > "$OUTPUT_FILE"

log_success "Written: $OUTPUT_FILE"

# ---------------------------------------------------------------------------
# Emit structured output lines for the wizard's _extract_outputs parser
# (execute.py reads these to surface the IDs in the run summary)
# ---------------------------------------------------------------------------
for key in "${GROUP_KEYS[@]}"; do
  [[ -n "${ID_MAP[$key]+x}" ]] || continue
  echo "AIM_GROUP_${key}_ID=${ID_MAP[$key]}"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=========================================================="
echo "Azure AD Groups Ready ✅"
echo "=========================================================="
echo ""
echo "  Environment : ${ENV_SUFFIX}"
echo "  Groups      : ${#ID_MAP[@]} created/verified"
echo ""
for key in "${GROUP_KEYS[@]}"; do
  [[ -n "${ID_MAP[$key]+x}" ]] || continue
  printf "  %-12s → %s\n" "$key" "${GROUP_NAMES[$key]}"
done
echo ""
echo "  IDs file    : infra/envs/${ENV}/.aim-group-ids.json"
echo ""
echo "Next: click 'Save' in the wizard — group IDs will be"
echo "embedded in identity.tfvars automatically. Terraform will"
echo "use them directly via aim_group_ids (no Group.ReadWrite.All"
echo "required for the CI/CD service principal)."
echo "=========================================================="
