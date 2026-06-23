#!/bin/bash
# ==========================================================
# Bootstrap CI/CD Service Principal for GitHub Actions
# ==========================================================
#
# This script performs the one-time setup that cannot be automated
# via OpenTofu (the SP must exist before OpenTofu can run):
#
#   1. Creates an Azure AD App Registration + Service Principal
#   2. Assigns Azure roles (Contributor, User Access Administrator)
#   3. Creates federated credentials (OIDC — no secrets for OpenTofu)
#   4. Creates a client secret (for Databricks CLI authentication)
#   5. Assigns Storage Blob Data Contributor on the OpenTofu state backend
#   6. Sets GitHub repository variables and secrets via gh CLI
#   7. Creates GitHub environments (dev: auto-deploy, prod: required reviewers)
#   8. Updates infra/envs/<env>/{env}.tfvars with cicd_sp_application_id
#
# After running this script, run `tofu apply` to register the SP
# in Databricks automatically.
#
# Usage:
#   ./scripts/bootstrap-cicd.sh [environment] [--prod-reviewer GITHUB_USERNAME]
#
# Examples:
#   ./scripts/bootstrap-cicd.sh dev
#   ./scripts/bootstrap-cicd.sh prod --prod-reviewer octocat
#
# Prerequisites:
#   - Azure CLI (az) installed and authenticated (az login)
#   - GitHub CLI (gh) installed and authenticated (gh auth login)
#   - jq installed (brew install jq)
#   - Repository cloned locally, run from repo root
#   - OpenTofu state backend created (scripts/create-backend.sh)

set -euo pipefail

# ==========================================================
# Configuration
# ==========================================================

ENVIRONMENT="dev"
PROD_REVIEWER=""
# Reuse an explicit existing SP (adopted in the wizard) instead of creating a
# new slug-named one — env var or --use-existing-app-id. One SP can then serve
# multiple repos/instances (this run just adds the current repo's fed-creds +
# the state-backend role to it).
CICD_SP_APP_ID="${CICD_SP_APP_ID:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    dev|prod|sandbox)       ENVIRONMENT="$1"; shift ;;
    --prod-reviewer)        PROD_REVIEWER="${2:-}"; shift 2 ;;
    --emit-local-creds)     export EMIT_LOCAL_SP_CREDS=1; shift ;;
    --use-existing-app-id)  CICD_SP_APP_ID="${2:-}"; shift 2 ;;
    *) echo "Unknown argument: $1"; echo "Usage: $0 [dev|prod] [--prod-reviewer USERNAME] [--emit-local-creds] [--use-existing-app-id APP_ID]"; exit 1 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
GITHUB_REPO="${GITHUB_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")}"

# Project slug namespaces the SP so multiple blueprint instances can coexist in
# one tenant. See scripts/lib/project-slug.sh.
source "$(dirname "${BASH_SOURCE[0]}")/lib/project-slug.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/prompt.sh"
SLUG="$(resolve_project_slug)"

# SP naming (fed-cred names below are children of this SP, so they stay per-SP).
APP_NAME="GitHub-Actions-${SLUG}-${ENVIRONMENT}"
SECRET_DISPLAY_NAME="github-actions-databricks"
SECRET_YEARS=2

# ==========================================================
# Color Output
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }

# ==========================================================
# Prerequisites Check
# ==========================================================

log_step "Checking prerequisites"

for cmd in az gh jq; do
  if ! command -v "$cmd" &>/dev/null; then
    log_error "Required tool not found: $cmd"
    case "$cmd" in
      az)  echo "  Install: https://docs.microsoft.com/cli/azure/install-azure-cli" ;;
      gh)  echo "  Install: brew install gh  (or https://cli.github.com)" ;;
      jq)  echo "  Install: brew install jq" ;;
    esac
    exit 1
  fi
done

if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login' first."
  exit 1
fi

if ! gh auth status &>/dev/null; then
  log_error "Not logged in to GitHub CLI. Run 'gh auth login' first."
  exit 1
fi

if [[ -z "$GITHUB_REPO" ]]; then
  log_error "Could not determine GitHub repository. Set GITHUB_REPO=org/repo or run from repo root."
  exit 1
fi

if [[ ! "$ENVIRONMENT" =~ ^(dev|prod|sandbox)$ ]]; then
  log_warn "Non-standard environment: $ENVIRONMENT"
fi

# ==========================================================
# Azure Context
# ==========================================================

log_step "Reading Azure context"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)

log_info "Subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
log_info "Tenant:       $TENANT_ID"
log_info "Environment:  $ENVIRONMENT"
log_info "GitHub repo:  $GITHUB_REPO"
echo ""
if is_interactive; then
  read -rp "Proceed? (y/n) " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
else
  log_info "Non-interactive mode — proceeding without confirmation."
fi

# ==========================================================
# Step 1: App Registration
# ==========================================================

log_step "Step 1: Creating Azure AD App Registration"

if [[ -n "$CICD_SP_APP_ID" ]]; then
  # Reuse a specific existing SP (adopted in the wizard). Verify it exists, then
  # extend it below with this repo's fed-creds + roles instead of creating one.
  if ! az ad app show --id "$CICD_SP_APP_ID" >/dev/null 2>&1; then
    log_error "Requested app id '$CICD_SP_APP_ID' not found as an App Registration."
    exit 1
  fi
  APP_ID="$CICD_SP_APP_ID"
  APP_NAME=$(az ad app show --id "$APP_ID" --query displayName -o tsv)
  log_success "Reusing existing App Registration: $APP_NAME ($APP_ID)"
else
  # Check if app already exists by the conventional (slug-based) display name.
  EXISTING_APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")

  if [[ -n "$EXISTING_APP_ID" && "$EXISTING_APP_ID" != "None" ]]; then
    log_warn "App Registration '$APP_NAME' already exists (ID: $EXISTING_APP_ID)"
    log_warn "Reusing existing app. Run 'az ad app delete --id $EXISTING_APP_ID' to recreate."
    APP_ID="$EXISTING_APP_ID"
  else
    APP_ID=$(az ad app create \
      --display-name "$APP_NAME" \
      --query appId -o tsv)
    log_success "App Registration created: $APP_ID"
  fi
fi

# ==========================================================
# Step 2: Service Principal
# ==========================================================

log_step "Step 2: Creating Service Principal"

EXISTING_SP=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || echo "")

if [[ -n "$EXISTING_SP" && "$EXISTING_SP" != "None" ]]; then
  log_warn "Service Principal already exists (Object ID: $EXISTING_SP)"
  SP_OBJECT_ID="$EXISTING_SP"
else
  az ad sp create --id "$APP_ID" > /dev/null
  SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)
  log_success "Service Principal created (Object ID: $SP_OBJECT_ID)"
fi

# ==========================================================
# Step 3: Azure Role Assignments
# ==========================================================

log_step "Step 3: Assigning Azure roles"

SCOPE="/subscriptions/$SUBSCRIPTION_ID"

assign_role() {
  local role="$1"
  local scope="$2"
  if az role assignment list --assignee "$APP_ID" --role "$role" --scope "$scope" --query "[0].id" -o tsv 2>/dev/null | grep -q .; then
    log_warn "Role '$role' already assigned, skipping"
  else
    az role assignment create \
      --assignee "$APP_ID" \
      --role "$role" \
      --scope "$scope" > /dev/null
    log_success "Assigned role: $role"
  fi
}

assign_role "Contributor" "$SCOPE"
assign_role "User Access Administrator" "$SCOPE"

# ------------------------------------------------------------------
# Wait for RBAC propagation before continuing.
# Azure role assignments at subscription scope take 1–15 minutes to
# become visible in IAM — the SP won't have Contributor access until
# `az role assignment list` returns at least one entry. GitHub Actions
# starts within seconds of the PR merge that triggers it, so without
# this wait the first 'az login' step sees "No subscriptions found"
# and the OpenTofu plan fails.
# Poll every 15s for up to 10 minutes.
# ------------------------------------------------------------------
log_step "Waiting for Azure RBAC propagation (Contributor on subscription)"
RBAC_READY=false
for i in $(seq 1 40); do
  ROLE_CHECK=$(az role assignment list \
    --assignee "$APP_ID" \
    --role "Contributor" \
    --scope "$SCOPE" \
    --query "[0].id" -o tsv 2>/dev/null || echo "")
  if [[ -n "$ROLE_CHECK" ]]; then
    log_success "Contributor role visible in Azure IAM (attempt $i)"
    RBAC_READY=true
    break
  fi
  log_info "RBAC not propagated yet (attempt $i/40) — waiting 15s..."
  sleep 15
done
if [[ "$RBAC_READY" != "true" ]]; then
  log_warn "RBAC propagation timed out after 10 minutes — proceeding anyway."
  log_warn "If 'tofu apply' fails with 'No subscriptions found', re-run the workflow in ~5 minutes."
fi

# Microsoft Graph API — Application.ReadWrite.OwnedBy
# Only needed for prod: the databricks-workload-sp module creates an Azure AD app
# registration, and the CI/CD SP must own it (Application.ReadWrite.OwnedBy).
# Dev uses enable_workload_sp = false by default — skip this permission to avoid
# a 403 admin-consent error that the user cannot resolve without Global Admin rights.
if [[ "$ENVIRONMENT" == "prod" ]]; then
  GRAPH_API_ID="00000003-0000-0000-c000-000000000000"
  APP_RW_OWNED="18a4783c-866b-4cc7-a460-3d5e5662c884"  # Application.ReadWrite.OwnedBy
  log_step "Granting Microsoft Graph API permission: Application.ReadWrite.OwnedBy (prod only)"
  if az ad app permission list --id "$APP_ID" --query "[?resourceAppId=='$GRAPH_API_ID'].resourceAccess[].id" -o tsv 2>/dev/null | grep -q "$APP_RW_OWNED"; then
    log_warn "Application.ReadWrite.OwnedBy already granted, skipping"
  else
    az ad app permission add \
      --id "$APP_ID" \
      --api "$GRAPH_API_ID" \
      --api-permissions "${APP_RW_OWNED}=Role" > /dev/null 2>&1 || true
    # Capture output so AZ CLI error/warning text never leaks to the terminal.
    if az ad app permission admin-consent --id "$APP_ID" > /dev/null 2>&1; then
      log_success "Granted Application.ReadWrite.OwnedBy (admin consent applied)"
    else
      log_warn "Application.ReadWrite.OwnedBy added — admin consent requires a Global Admin."
      log_warn "Grant manually: Azure Portal → App registrations → $APP_NAME → API permissions → Grant admin consent"
    fi
  fi
else
  log_info "Skipping Application.ReadWrite.OwnedBy — not needed for dev (enable_workload_sp = false)"
fi

# Storage Blob Data Contributor on OpenTofu state backend (if it exists).
# Must match create-backend.sh, which namespaces the state RG by project_slug.
STATE_RG="rg-terraform-state-${SLUG}-${ENVIRONMENT}"
if az group show --name "$STATE_RG" &>/dev/null; then
  STATE_STORAGE_ID=$(az storage account list \
    --resource-group "$STATE_RG" \
    --query "[0].id" -o tsv 2>/dev/null || echo "")
  if [[ -n "$STATE_STORAGE_ID" && "$STATE_STORAGE_ID" != "None" ]]; then
    assign_role "Storage Blob Data Contributor" "$STATE_STORAGE_ID"
  else
    log_warn "No storage account found in $STATE_RG — run scripts/create-backend.sh $ENVIRONMENT first"
  fi
else
  log_warn "State backend resource group '$STATE_RG' not found — run scripts/create-backend.sh $ENVIRONMENT first"
fi

# ==========================================================
# Step 4: Federated Credentials (OIDC — no secrets for OpenTofu)
# ==========================================================

log_step "Step 4: Configuring Federated Credentials (OIDC)"

create_federated_credential() {
  local name="$1"
  local subject="$2"
  local description="$3"

  # Check if credential already exists
  if az ad app federated-credential list --id "$APP_ID" \
      --query "[?name=='$name'].name" -o tsv 2>/dev/null | grep -q "$name"; then
    log_warn "Federated credential '$name' already exists, skipping"
    return
  fi

  az ad app federated-credential create \
    --id "$APP_ID" \
    --parameters "{
      \"name\": \"$name\",
      \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"$subject\",
      \"description\": \"$description\",
      \"audiences\": [\"api://AzureADTokenExchange\"]
    }" > /dev/null
  log_success "Federated credential: $name"
}

if [[ "$ENVIRONMENT" == "prod" ]]; then
  # prod workflow has no `environment:` job key (avoids requiring paid GitHub plans),
  # so the OIDC subject is ref:refs/heads/main — same pattern as dev.
  create_federated_credential \
    "github-deploy-prod" \
    "repo:${GITHUB_REPO}:ref:refs/heads/main" \
    "Deploy to prod on push to main branch"

  create_federated_credential \
    "github-validate-pr-prod" \
    "repo:${GITHUB_REPO}:pull_request" \
    "Validate prod changes on pull requests"
else
  # GitOps best practice: main branch deploys to DEV environment
  create_federated_credential \
    "github-deploy-dev" \
    "repo:${GITHUB_REPO}:ref:refs/heads/main" \
    "Deploy to DEV environment on push to main branch"

  create_federated_credential \
    "github-validate-pr" \
    "repo:${GITHUB_REPO}:pull_request" \
    "Validate on pull requests"
fi

# ==========================================================
# Step 5: Client Secret (for Databricks CLI)
# ==========================================================

log_step "Step 5: Creating Client Secret (for Databricks CLI)"

log_info "Creating client secret (valid for $SECRET_YEARS years)..."
CLIENT_SECRET=$(az ad app credential reset \
  --id "$APP_ID" \
  --display-name "$SECRET_DISPLAY_NAME" \
  --years "$SECRET_YEARS" \
  --query password -o tsv)

SECRET_EXPIRY=$(date -v "+${SECRET_YEARS}y" "+%Y-%m-%d" 2>/dev/null || date --date="+${SECRET_YEARS} years" "+%Y-%m-%d")
log_success "Client secret created (expires: $SECRET_EXPIRY)"
log_warn "Secret rotation reminder: set a calendar reminder for $SECRET_EXPIRY"

# ----------------------------------------------------------
# Emit SP credentials so OpenTofu can run AS this dedicated SP.
# Writes a 0600 KEY=VALUE env file; the secret is NEVER printed to stdout.
# Two opt-in destinations (either/both):
#   WIZARD_EMIT_SP_ENV=1 + WIZARD_SP_ENV_FILE=<path>
#       → ephemeral file for the Setup Wizard's greenfield apply (the wizard
#         deletes it after CI/CD verification).
#   EMIT_LOCAL_SP_CREDS=1
#       → persistent infra/.sp-creds-<env>.env that tofu-wrapper.sh auto-sources
#         for local "test as the SP" runs. Gitignored. Delete it when done.
# Both are no-ops for a plain `bootstrap-cicd.sh <env>` CLI run.
# ----------------------------------------------------------
emit_sp_creds() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  ( umask 077
    cat > "$dest" <<EOF
# Generated by bootstrap-cicd.sh — DO NOT COMMIT. SP: $APP_ID
ARM_CLIENT_ID=$APP_ID
ARM_CLIENT_SECRET=$CLIENT_SECRET
ARM_TENANT_ID=$TENANT_ID
ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID
DATABRICKS_AZURE_CLIENT_ID=$APP_ID
DATABRICKS_AZURE_CLIENT_SECRET=$CLIENT_SECRET
DATABRICKS_AZURE_TENANT_ID=$TENANT_ID
EOF
  )
  chmod 600 "$dest" 2>/dev/null || true
}

if [[ "${WIZARD_EMIT_SP_ENV:-}" == "1" && -n "${WIZARD_SP_ENV_FILE:-}" ]]; then
  emit_sp_creds "$WIZARD_SP_ENV_FILE"
  log_success "SP credentials emitted for the Setup Wizard (greenfield apply will run as this SP)."
fi

if [[ "${EMIT_LOCAL_SP_CREDS:-}" == "1" ]]; then
  LOCAL_SP_CREDS_FILE="${REPO_ROOT}/infra/.sp-creds-${ENVIRONMENT}.env"
  emit_sp_creds "$LOCAL_SP_CREDS_FILE"
  log_success "Local SP credentials written: infra/.sp-creds-${ENVIRONMENT}.env (gitignored)."
  log_info "  Test as the SP:  ./scripts/tofu-wrapper.sh ${ENVIRONMENT} plan"
  log_warn "  This file holds a live client secret — delete it when you're done testing."
fi

# ==========================================================
# Step 6: Set GitHub Variables and Secrets
# ==========================================================

log_step "Step 6: Configuring GitHub repository"

if [[ "$ENVIRONMENT" == "prod" ]]; then
  VAR_CLIENT_ID="AZURE_PROD_CLIENT_ID"
  VAR_SUBSCRIPTION_ID="AZURE_PROD_SUBSCRIPTION_ID"
  SECRET_CLIENT_SECRET="AZURE_PROD_CLIENT_SECRET"
else
  VAR_CLIENT_ID="AZURE_CLIENT_ID"
  VAR_SUBSCRIPTION_ID="AZURE_SUBSCRIPTION_ID"
  SECRET_CLIENT_SECRET="AZURE_CLIENT_SECRET"
fi

set_gh_variable() {
  local name="$1"
  local value="$2"
  gh variable set "$name" --body "$value" --repo "$GITHUB_REPO"
  log_success "GitHub variable set: $name"
}

set_gh_secret() {
  local name="$1"
  local value="$2"
  echo "$value" | gh secret set "$name" --repo "$GITHUB_REPO"
  log_success "GitHub secret set: $name"
}

set_gh_variable "$VAR_CLIENT_ID"       "$APP_ID"
set_gh_variable "$VAR_SUBSCRIPTION_ID" "$SUBSCRIPTION_ID"
set_gh_variable "AZURE_TENANT_ID"      "$TENANT_ID"       # idempotent — same for dev+prod
set_gh_secret   "$SECRET_CLIENT_SECRET" "$CLIENT_SECRET"

# ----------------------------------------------------------
# DATABRICKS_ACCOUNT_ID — prompt if not provided via env var
# ----------------------------------------------------------
if [[ -z "${DATABRICKS_ACCOUNT_ID:-}" ]] && is_interactive; then
  log_step "Databricks Account ID"
  log_info "Find your Account ID at: https://accounts.azuredatabricks.net"
  log_info "(Log in → click your name in the top-right corner → Account ID)"
  echo ""
  read -rp "Enter Databricks Account ID (leave blank to skip): " DATABRICKS_ACCOUNT_ID
fi
if [[ -n "${DATABRICKS_ACCOUNT_ID:-}" ]]; then
  set_gh_variable "DATABRICKS_ACCOUNT_ID" "$DATABRICKS_ACCOUNT_ID"
else
  log_warn "DATABRICKS_ACCOUNT_ID skipped — set manually later:"
  log_warn "  gh variable set DATABRICKS_ACCOUNT_ID --body <id> --repo $GITHUB_REPO"
fi

log_info "Note: DATABRICKS_DEV_HOST and DATABRICKS_PROD_HOST must be set after OpenTofu apply"
log_info "      Run: scripts/setup-github-vars.sh ${ENVIRONMENT}"

# ----------------------------------------------------------
# GH_VARIABLE_TOKEN — PAT required by deploy workflows to
# write repository variables (GITHUB_TOKEN lacks variables:write)
# ----------------------------------------------------------
log_step "GitHub Variable Token (GH_VARIABLE_TOKEN)"
log_info "The deploy workflow sets GitHub variables automatically after 'tofu apply'."
log_info "This requires a Classic PAT with 'repo' scope — GITHUB_TOKEN cannot write variables."
log_info ""
log_info "Create one at: https://github.com/settings/tokens?type=legacy"
log_info "  Required scope: repo (full)"
log_info "  Recommended expiry: 1 year"
log_info ""
if [[ -z "${GH_VARIABLE_TOKEN:-}" ]] && is_interactive; then
  read -rsp "Paste the PAT (input hidden, blank to skip): " GH_VARIABLE_TOKEN
  echo ""
fi
# Non-interactive fallback (wizard context): use the currently-authenticated gh token.
# gh OAuth tokens already carry repo scope when authenticated via the wizard flow.
if [[ -z "${GH_VARIABLE_TOKEN:-}" ]] && ! is_interactive; then
  _fallback_gh_token="$(gh auth token 2>/dev/null || echo "")"
  if [[ -n "$_fallback_gh_token" ]]; then
    GH_VARIABLE_TOKEN="$_fallback_gh_token"
    log_info "Using currently-authenticated gh token as GH_VARIABLE_TOKEN"
  fi
fi
if [[ -n "${GH_VARIABLE_TOKEN:-}" ]]; then
  set_gh_secret "GH_VARIABLE_TOKEN" "$GH_VARIABLE_TOKEN"
else
  log_warn "GH_VARIABLE_TOKEN skipped — set manually later:"
  log_warn "  gh secret set GH_VARIABLE_TOKEN --repo $GITHUB_REPO"
fi

# ==========================================================
# Step 7: Create GitHub Environments
# ==========================================================

log_step "Step 7: Creating GitHub Environments"

create_gh_environment() {
  local env_name="$1"
  local payload="$2"
  if echo "$payload" | gh api --method PUT "repos/$GITHUB_REPO/environments/$env_name" \
      --input - > /dev/null 2>&1; then
    log_success "GitHub environment created: $env_name"
  else
    log_warn "Could not create GitHub environment '$env_name' (requires repo admin access)"
  fi
}

# Dev: auto-deploy on push to main, no required reviewers
create_gh_environment "dev" '{}'

# Prod: required reviewers (if --prod-reviewer provided) or created without
if [[ -n "$PROD_REVIEWER" ]]; then
  REVIEWER_ID=$(gh api "users/$PROD_REVIEWER" --jq '.id' 2>/dev/null || echo "")
  if [[ -n "$REVIEWER_ID" && "$REVIEWER_ID" != "null" ]]; then
    PROD_PAYLOAD=$(printf '{"reviewers":[{"type":"User","id":%s}],"prevent_self_review":true}' "$REVIEWER_ID")
    create_gh_environment "prod" "$PROD_PAYLOAD"
    log_info "  Required reviewer configured: $PROD_REVIEWER"
  else
    log_warn "GitHub user '$PROD_REVIEWER' not found — creating prod environment without reviewers"
    create_gh_environment "prod" '{}'
    log_warn "Add required reviewers manually: https://github.com/$GITHUB_REPO/settings/environments → prod"
  fi
else
  create_gh_environment "prod" '{}'
  log_warn "No --prod-reviewer provided. Add required reviewers for the prod environment:"
  log_warn "  https://github.com/$GITHUB_REPO/settings/environments → prod → Required reviewers"
  log_warn "  Or rerun: ./scripts/bootstrap-cicd.sh prod --prod-reviewer YOUR_GITHUB_USERNAME"
fi

# ==========================================================
# Step 8b: Grant Databricks Account Admin to CI/CD SP
# ==========================================================
# The CI/CD SP needs account_admin in Databricks to manage groups (AIM module)
# and read account-level resources during tofu plan/apply.
#
# This uses the Databricks Account SCIM API with an Azure-issued token.
# If the SP does not yet exist in Databricks (first bootstrap, before tofu apply),
# it is pre-registered here so OpenTofu can manage it from the first run.
#
# Note: OpenTofu's databricks_service_principal will import/update the existing SP
# without conflict because it uses applicationId as the lookup key.

log_step "Step 8b: Granting Databricks Account Admin to CI/CD SP"

if [[ -z "${DATABRICKS_ACCOUNT_ID:-}" ]]; then
  log_warn "DATABRICKS_ACCOUNT_ID not set — skipping Databricks Account Admin grant"
  log_warn "Run this script again after setting DATABRICKS_ACCOUNT_ID, or grant manually:"
  log_warn "  Databricks Account Console → User Management → Service Principals → $APP_NAME → Roles → Account Admin"
else
  # Get Azure token for Databricks (resource ID is fixed for all Azure Databricks tenants)
  DATABRICKS_TOKEN=$(az account get-access-token \
    --resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" \
    --query accessToken -o tsv 2>/dev/null || echo "")

  if [[ -z "$DATABRICKS_TOKEN" ]]; then
    log_warn "Could not obtain Databricks token — skipping Account Admin grant"
    log_warn "Grant manually in Databricks Account Console"
  else
    # SCIM v2 endpoint — the bare /servicePrincipals path 303-redirects and returns
    # nothing, which is why this whole block silently no-op'd before.
    ACCOUNT_API="https://accounts.azuredatabricks.net/api/2.0/accounts/${DATABRICKS_ACCOUNT_ID}/scim/v2"

    # Check if SP already exists in Databricks account
    EXISTING_DB_SP=$(curl -sf \
      -H "Authorization: Bearer $DATABRICKS_TOKEN" \
      "${ACCOUNT_API}/ServicePrincipals?filter=applicationId%20eq%20%22${APP_ID}%22" 2>/dev/null | \
      jq -r '.Resources[0].id // empty' 2>/dev/null || echo "")

    if [[ -n "$EXISTING_DB_SP" ]]; then
      # SP exists — patch to add account_admin role
      PATCH_RESULT=$(curl -sf -X PATCH \
        -H "Authorization: Bearer $DATABRICKS_TOKEN" \
        -H "Content-Type: application/json" \
        "${ACCOUNT_API}/ServicePrincipals/${EXISTING_DB_SP}" \
        -d '{
          "schemas": ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
          "Operations": [{"op": "add", "path": "roles", "value": [{"value": "account_admin"}]}]
        }' 2>/dev/null && echo "ok" || echo "failed")

      if [[ "$PATCH_RESULT" == "ok" ]]; then
        log_success "Databricks Account Admin granted to SP (Databricks ID: $EXISTING_DB_SP)"
        log_warn "Account-admin can take a few minutes to propagate — if 'tofu apply' fails with"
        log_warn "'API is disabled for users without account admin status', just re-run it."
      else
        log_warn "Could not patch SP — grant manually in Databricks Account Console"
      fi
    else
      # SP not yet in Databricks — create it, then grant account_admin via PATCH.
      # NOTE: applicationId MUST be a quoted JSON string and the SCIM schema must
      # be present; the previous inline `$(echo "$APP_ID" | tr -d '"')` emitted the
      # GUID unquoted → invalid JSON → the create silently failed and the SP never
      # got account_admin.
      NEW_DB_SP=$(curl -sf -X POST \
        -H "Authorization: Bearer $DATABRICKS_TOKEN" \
        -H "Content-Type: application/json" \
        "${ACCOUNT_API}/ServicePrincipals" \
        -d "{
          \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:ServicePrincipal\"],
          \"applicationId\": \"$APP_ID\",
          \"displayName\": \"$APP_NAME\"
        }" 2>/dev/null | jq -r '.id // empty' || echo "")

      if [[ -z "$NEW_DB_SP" ]]; then
        log_warn "Could not pre-register SP in Databricks — grant manually after tofu apply:"
        log_warn "  Databricks Account Console → User Management → Service Principals → $APP_NAME → Roles → Account Admin"
      elif curl -sf -X PATCH \
          -H "Authorization: Bearer $DATABRICKS_TOKEN" \
          -H "Content-Type: application/json" \
          "${ACCOUNT_API}/ServicePrincipals/${NEW_DB_SP}" \
          -d '{"schemas":["urn:ietf:params:scim:api:messages:2.0:PatchOp"],"Operations":[{"op":"add","path":"roles","value":[{"value":"account_admin"}]}]}' \
          >/dev/null 2>&1; then
        log_success "SP pre-registered in Databricks with Account Admin (ID: $NEW_DB_SP)"
        log_info "OpenTofu will import and manage this SP — no conflict expected"
        log_warn "Account-admin can take a few minutes to propagate — if the first 'tofu apply'"
        log_warn "fails with 'API is disabled for users without account admin status', just re-run it."
      else
        log_warn "SP created (ID: $NEW_DB_SP) but the Account Admin grant failed — set it manually:"
        log_warn "  Databricks Account Console → User Management → Service Principals → $APP_NAME → Roles → Account Admin"
      fi
    fi
  fi
fi

# ==========================================================
# Step 8: Update {env}.tfvars
# ==========================================================

log_step "Step 8: Updating ${ENVIRONMENT}.tfvars"

TFVARS_FILE="${REPO_ROOT}/infra/envs/${ENVIRONMENT}/${ENVIRONMENT}.tfvars"

if [[ -f "$TFVARS_FILE" ]]; then
  if grep -q "cicd_sp_application_id" "$TFVARS_FILE"; then
    # Uncomment and set the value
    sed -i.bak \
      "s|# *cicd_sp_application_id *= *\".*\"|cicd_sp_application_id = \"$APP_ID\"|g" \
      "$TFVARS_FILE"
    rm -f "${TFVARS_FILE}.bak"
    log_success "Updated cicd_sp_application_id in $TFVARS_FILE"
  else
    log_warn "cicd_sp_application_id not found in $TFVARS_FILE — add manually:"
    echo "  cicd_sp_application_id = \"$APP_ID\""
  fi
else
  log_warn "${ENVIRONMENT}.tfvars not found at $TFVARS_FILE"
  log_warn "Copy ${ENVIRONMENT}.tfvars.example and add: cicd_sp_application_id = \"$APP_ID\""
fi

# ==========================================================
# Step 9: Pre-create Azure AD groups (as logged-in user)
# ==========================================================
# Creates the five Databricks security groups using the currently-authenticated
# Azure user — regular users can create security groups in most tenants, so no
# Group.ReadWrite.All application permission is needed. The group object IDs are
# written to infra/envs/${ENVIRONMENT}/.aim-group-ids.json so the wizard embeds
# them into identity.tfvars on Save, letting Terraform reference groups by ID
# without any Azure AD API calls from the CI/CD service principal.

log_step "Step 9: Pre-creating Azure AD groups for Databricks AIM"
log_info "Creating groups as the currently-authenticated Azure user."
log_info "No Group.ReadWrite.All permission required — regular users can create security groups."

GROUPS_SCRIPT="${REPO_ROOT}/scripts/create-azure-groups.sh"
if [[ -f "$GROUPS_SCRIPT" ]]; then
  bash "$GROUPS_SCRIPT" "$ENVIRONMENT" || {
    _groups_exit=$?
    log_warn "Group pre-creation exited with code $_groups_exit — CI/CD bootstrap is still complete."
    log_warn "Run manually before clicking Save in the wizard:"
    log_warn "  ./scripts/create-azure-groups.sh $ENVIRONMENT"
    log_warn "If your tenant blocks group creation, contact your Azure AD administrator."
  }
else
  log_warn "create-azure-groups.sh not found at $GROUPS_SCRIPT — run it manually before Save:"
  log_warn "  ./scripts/create-azure-groups.sh $ENVIRONMENT"
fi

# ==========================================================
# Summary
# ==========================================================

echo ""
echo "=========================================================="
echo "CI/CD Bootstrap Complete! ✅"
echo "=========================================================="
echo ""
echo "📋 Service Principal:"
echo "   Display Name:  $APP_NAME"
echo "   Application ID (AZURE_CLIENT_ID):  $APP_ID"
echo "   Object ID:     $SP_OBJECT_ID"
echo "   Tenant ID:     $TENANT_ID"
echo ""
echo "🔑 GitHub Secrets set:"
echo "   $SECRET_CLIENT_SECRET  ← stored securely in GitHub (not shown)"
if [[ -n "${GH_VARIABLE_TOKEN:-}" ]]; then
  echo "   GH_VARIABLE_TOKEN      ← stored securely in GitHub (not shown)"
fi
echo ""
echo "📝 GitHub Variables set:"
echo "   $VAR_CLIENT_ID         = $APP_ID"
echo "   $VAR_SUBSCRIPTION_ID   = $SUBSCRIPTION_ID"
echo "   AZURE_TENANT_ID        = $TENANT_ID"
if [[ -n "${DATABRICKS_ACCOUNT_ID:-}" ]]; then
  echo "   DATABRICKS_ACCOUNT_ID  = $DATABRICKS_ACCOUNT_ID"
fi
echo ""
echo "📅 Secret Rotation:"
echo "   Client secret expires: $SECRET_EXPIRY"
echo "   To rotate: az ad app credential reset --id $APP_ID --display-name $SECRET_DISPLAY_NAME"
echo "   Then update GitHub secret: gh secret set $SECRET_CLIENT_SECRET --repo $GITHUB_REPO"
echo ""
echo "📝 Next Steps:"
echo ""
echo "   1. Register SP in Databricks (automatic via OpenTofu):"
echo "      cd infra/envs/${ENVIRONMENT}"
echo "      tofu apply"
echo ""
echo "   2. Set workspace URL + bundle variables after apply:"
echo "      ./scripts/setup-github-vars.sh ${ENVIRONMENT}"
echo ""
echo "   3. Create PR targeting the '${ENVIRONMENT}' branch to trigger CI/CD."
echo ""
echo "=========================================================="
