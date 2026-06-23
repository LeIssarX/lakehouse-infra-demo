#!/bin/bash
# ==========================================================
# setup-github-vars.sh <environment>
# ==========================================================
#
# Reads OpenTofu outputs and sets the GitHub repository variables
# consumed by bundle-deploy.yml during CI/CD runs.
#
# Run this once after the first 'tofu apply' and before the first
# CI/CD pipeline run, or whenever infrastructure outputs change.
#
# Usage:
#   ./scripts/setup-github-vars.sh dev
#   ./scripts/setup-github-vars.sh prod
#
# Prerequisites:
#   - GitHub CLI (gh) authenticated (gh auth login)
#   - OpenTofu state available (tofu apply already run for the environment)
#   - jq installed (brew install jq)
#   - Run from repo root

set -euo pipefail

# ==========================================================
# Configuration
# ==========================================================

ENVIRONMENT="${1:-dev}"
ENV_UPPER="$(echo "$ENVIRONMENT" | tr '[:lower:]' '[:upper:]')"
ENV_DIR="infra/envs/${ENVIRONMENT}"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
GITHUB_REPO="${GITHUB_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")}"

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
# Prerequisites
# ==========================================================

log_step "Checking prerequisites"

for cmd in gh tofu jq; do
  if ! command -v "$cmd" &>/dev/null; then
    log_error "Required tool not found: $cmd"
    case "$cmd" in
      gh)   echo "  Install: brew install gh  (or https://cli.github.com)" ;;
      tofu) echo "  Install: https://opentofu.org/docs/intro/install/" ;;
      jq)   echo "  Install: brew install jq" ;;
    esac
    exit 1
  fi
done

if ! gh auth status &>/dev/null; then
  log_error "Not logged in to GitHub CLI. Run 'gh auth login' first."
  exit 1
fi

if [[ -z "$GITHUB_REPO" ]]; then
  log_error "Could not determine GitHub repository. Set GITHUB_REPO=org/repo or run from repo root."
  exit 1
fi

if [[ ! -d "${REPO_ROOT}/${ENV_DIR}" ]]; then
  log_error "Environment directory not found: ${ENV_DIR}"
  exit 1
fi

log_info "Environment: $ENVIRONMENT"
log_info "GitHub repo: $GITHUB_REPO"

# ==========================================================
# Read OpenTofu Outputs
# ==========================================================

log_step "Reading OpenTofu outputs for '${ENVIRONMENT}'"

# Outputs live in the flat root module (infra/), not the per-env var-file dir
# (infra/envs/$ENV holds only *.tfvars + backend.hcl). The env's state must
# already be initialised here (tofu init -backend-config=envs/$ENV/backend.hcl),
# which the deploy step / wrapper does before apply.
cd "${REPO_ROOT}/infra"

WORKSPACE_URL=$(tofu output -raw databricks_workspace_url 2>/dev/null || echo "")
CATALOG_NAME=$(tofu output -raw unity_catalog_catalog_name 2>/dev/null || echo "")
TAGS_JSON=$(tofu output -json tags 2>/dev/null || echo "{}")

if [[ -z "$WORKSPACE_URL" ]]; then
  log_error "Could not read 'databricks_workspace_url' from tofu output."
  log_error "Make sure 'tofu apply' has completed successfully for the '${ENVIRONMENT}' environment."
  exit 1
fi

if [[ -z "$CATALOG_NAME" ]]; then
  log_warn "Could not read 'unity_catalog_catalog_name' — using default 'lakehouse_${ENVIRONMENT}'"
  CATALOG_NAME="lakehouse_${ENVIRONMENT}"
fi

TAG_PROJECT=$(echo "$TAGS_JSON"    | jq -r '.Project    // "Azure Lakehouse Blueprint"')
TAG_OWNER=$(echo "$TAGS_JSON"      | jq -r '.Owner      // "DataPlatformTeam"')
TAG_COST_CENTER=$(echo "$TAGS_JSON" | jq -r '.CostCenter // "Engineering"')

log_info "Workspace URL:  $WORKSPACE_URL"
log_info "Catalog name:   $CATALOG_NAME"
log_info "Tag.Project:    $TAG_PROJECT"
log_info "Tag.Owner:      $TAG_OWNER"
log_info "Tag.CostCenter: $TAG_COST_CENTER"

cd "${REPO_ROOT}"

# ==========================================================
# Set GitHub Variables
# ==========================================================

log_step "Setting GitHub repository variables"

set_gh_variable() {
  local name="$1"
  local value="$2"
  gh variable set "$name" --body "$value" --repo "$GITHUB_REPO"
  log_success "GitHub variable set: $name"
}

set_gh_variable "DATABRICKS_${ENV_UPPER}_HOST"     "$WORKSPACE_URL"
set_gh_variable "BUNDLE_${ENV_UPPER}_CATALOG_NAME" "$CATALOG_NAME"
set_gh_variable "BUNDLE_TAG_PROJECT"               "$TAG_PROJECT"
set_gh_variable "BUNDLE_TAG_OWNER"                 "$TAG_OWNER"
set_gh_variable "BUNDLE_TAG_COST_CENTER"           "$TAG_COST_CENTER"

# ==========================================================
# Summary
# ==========================================================

echo ""
echo "=========================================================="
echo "GitHub Variables Set! ✅"
echo "=========================================================="
echo ""
echo "📝 Variables configured:"
echo "   DATABRICKS_${ENV_UPPER}_HOST     = $WORKSPACE_URL"
echo "   BUNDLE_${ENV_UPPER}_CATALOG_NAME = $CATALOG_NAME"
echo "   BUNDLE_TAG_PROJECT               = $TAG_PROJECT"
echo "   BUNDLE_TAG_OWNER                 = $TAG_OWNER"
echo "   BUNDLE_TAG_COST_CENTER           = $TAG_COST_CENTER"
echo ""
echo "📝 Verify with:"
echo "   gh variable list --repo $GITHUB_REPO"
echo ""
echo "📝 Next Step:"
echo "   Create a PR targeting the '${ENVIRONMENT}' branch to trigger CI/CD."
echo "=========================================================="
