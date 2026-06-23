#!/bin/bash
# ==========================================================
# OpenTofu Wrapper Script
# ==========================================================
# Runs OpenTofu from infra/ (flat root module) with environment-
# specific backend config and variable files.
#
# Usage:
#   ./scripts/tofu-wrapper.sh dev plan
#   ./scripts/tofu-wrapper.sh prod apply
#   ./scripts/tofu-wrapper.sh dev apply -auto-approve
#
# This script simplifies the command from:
#   cd infra
#   tofu init -backend-config=envs/dev/backend.hcl -reconfigure
#   tofu plan -var-file=common.tfvars -var-file=envs/dev/dev.tfvars
#
# To:
#   ./scripts/tofu-wrapper.sh dev plan
# ==========================================================

set -euo pipefail

# ==========================================================
# Configuration
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$REPO_ROOT/infra"

# ==========================================================
# Helper Functions
# ==========================================================

usage() {
  cat <<EOF
Usage: $0 <environment> <tofu-command> [tofu-args...]

Automatically loads common.tfvars and environment-specific .tfvars files.

Arguments:
  <environment>    Environment name (dev, prod)
  <tofu-command>   OpenTofu command (init, plan, apply, destroy, etc.)
  [tofu-args...]   Additional arguments passed to OpenTofu

Examples:
  $0 dev init              # Initialize dev environment
  $0 dev plan              # Plan changes for dev
  $0 prod apply            # Apply changes to prod
  $0 dev apply -auto-approve  # Auto-approve apply
  $0 dev destroy           # Destroy dev resources

Files loaded (in order):
  1. infra/common.tfvars              # Global values
  2. infra/envs/{env}/{env}.tfvars    # Environment core (naming, network, security, tags)
  3. infra/envs/{env}/*.tfvars        # Domain siblings, if present (grants, identity, compute)

Backend config:
  infra/envs/{env}/backend.hcl        # Loaded via -backend-config at init

Working directory:
  infra/                              # Flat root module — same code for all envs

Environment variables required:
  ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID

EOF
  exit 1
}

check_requirements() {
  # Check if tofu is installed
  if ! command -v tofu &> /dev/null; then
    echo "❌ ERROR: OpenTofu CLI not found"
    echo ""
    echo "Install OpenTofu:"
    echo "  macOS:   brew install opentofu"
    echo "  Linux:   https://opentofu.org/docs/intro/install/"
    echo ""
    exit 1
  fi

  # Check Azure credentials
  if [[ -z "${ARM_CLIENT_ID:-}" ]] || \
     [[ -z "${ARM_CLIENT_SECRET:-}" ]] || \
     [[ -z "${ARM_TENANT_ID:-}" ]] || \
     [[ -z "${ARM_SUBSCRIPTION_ID:-}" ]]; then
    echo "⚠️  WARNING: Azure credentials not set"
    echo ""
    echo "Set these environment variables:"
    echo "  export ARM_CLIENT_ID=\"...\""
    echo "  export ARM_CLIENT_SECRET=\"...\""
    echo "  export ARM_TENANT_ID=\"...\""
    echo "  export ARM_SUBSCRIPTION_ID=\"...\""
    echo ""
    echo "Continuing anyway (may fail during provider initialization)..."
    echo ""
  fi
}

validate_environment() {
  local ENV=$1
  
  # Check if environment directory exists
  if [[ ! -d "$INFRA_DIR/envs/$ENV" ]]; then
    echo "❌ ERROR: Environment directory not found: infra/envs/$ENV"
    echo ""
    echo "Available environments:"
    for dir in "$INFRA_DIR/envs"/*; do
      if [[ -d "$dir" ]]; then
        echo "  - $(basename "$dir")"
      fi
    done
    echo ""
    exit 1
  fi

  # Check if common.tfvars exists
  if [[ ! -f "$INFRA_DIR/common.tfvars" ]]; then
    echo "❌ ERROR: Common variables file not found: infra/common.tfvars"
    echo ""
    echo "This file should be in git. Pull latest or create from template:"
    echo "  git pull  # or: cp infra/common.tfvars.example infra/common.tfvars"
    echo "  # Edit with your account ID, location, etc."
    echo ""
    exit 1
  fi

  # Check if environment-specific .tfvars exists (core file is mandatory;
  # sibling domain files like grants.tfvars / identity.tfvars / compute.tfvars
  # are optional and loaded only if present).
  if [[ ! -f "$INFRA_DIR/envs/$ENV/$ENV.tfvars" ]]; then
    echo "❌ ERROR: Environment variables file not found: infra/envs/$ENV/$ENV.tfvars"
    echo ""
    echo "This file should be in git. Pull latest or create from template:"
    echo "  git pull  # or: cp infra/envs/$ENV/$ENV.tfvars.example infra/envs/$ENV/$ENV.tfvars"
    echo "  # Edit with environment-specific values"
    echo ""
    exit 1
  fi
}

# Build the list of -var-file flags for the environment, ordered as:
#   1. core: envs/$ENV/$ENV.tfvars (always first)
#   2. domain siblings: envs/$ENV/*.tfvars in alphabetical order
# Returns the flags on stdout, space-separated.
build_var_files() {
  local ENV=$1
  local flags=("-var-file=envs/$ENV/$ENV.tfvars")
  shopt -s nullglob
  for f in "$INFRA_DIR/envs/$ENV"/*.tfvars; do
    local base
    base=$(basename "$f")
    if [[ "$base" != "$ENV.tfvars" ]]; then
      flags+=("-var-file=envs/$ENV/$base")
    fi
  done
  shopt -u nullglob
  echo "${flags[@]}"
}

# Adopt the pre-registered account-level CI/CD service principal into the state
# before the first apply (idempotent). The logic lives in scripts/import-cicd-sp.sh
# so the CI deploy workflows can reuse it. Must run after auth is set up.
maybe_import_cicd_sp() {
  local helper="$REPO_ROOT/scripts/import-cicd-sp.sh"
  [[ -x "$helper" ]] || return 0
  "$helper" "$ENV" || true
}

# ==========================================================
# Main Script
# ==========================================================

# Check arguments
if [[ $# -lt 2 ]]; then
  usage
fi

ENV="$1"
TOFU_CMD="$2"
shift 2
TOFU_ARGS=("$@")

# Validate setup
check_requirements
validate_environment "$ENV"

# Paths
INFRA_DIR_ABS="$INFRA_DIR"
BACKEND_HCL="$INFRA_DIR/envs/$ENV/backend.hcl"
COMMON_TFVARS="$INFRA_DIR/common.tfvars"
ENV_TFVARS="$INFRA_DIR/envs/$ENV/$ENV.tfvars"
ENV_VAR_FILES=$(build_var_files "$ENV")

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  OpenTofu Wrapper                                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Environment:     $ENV"
echo "Command:         $TOFU_CMD ${TOFU_ARGS[*]:-}"
echo "Working Dir:     $INFRA_DIR"
echo ""
echo "Loading:"
echo "  Backend:       envs/$ENV/backend.hcl"
echo "  Variables:     common.tfvars + envs/$ENV/*.tfvars"
echo ""

# Change to infra/ directory (flat root module)
cd "$INFRA_DIR"

# Build command
case "$TOFU_CMD" in
  init)
    # Always pass -backend-config and -reconfigure for correct env backend
    FULL_CMD="tofu init -backend-config=envs/$ENV/backend.hcl -reconfigure ${TOFU_ARGS[*]:-}"
    ;;
  fmt|version|providers|force-unlock)
    # These commands don't need var-files or backend-config
    FULL_CMD="tofu $TOFU_CMD ${TOFU_ARGS[*]:-}"
    ;;
  state)
    # State commands need backend but not var-files
    FULL_CMD="tofu $TOFU_CMD ${TOFU_ARGS[*]:-}"
    ;;
  *)
    # All plan/apply/destroy/validate etc. need every -var-file (common + env split)
    FULL_CMD="tofu $TOFU_CMD -var-file=common.tfvars $ENV_VAR_FILES ${TOFU_ARGS[*]:-}"
    ;;
esac

echo "Executing:"
echo "  $FULL_CMD"
echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""

# ==========================================================
# Databricks Authentication
# ==========================================================
#
# Auth resolution (local), best → fallback. Override with TOFU_LOCAL_AUTH=sp|azcli|profile.
#
#   1. sp      — Service Principal (ARM_CLIENT_ID/SECRET/TENANT/SUBSCRIPTION set,
#                or sourced from a creds file). Full parity with CI: account-level
#                modules (AIM, workload_sp) work locally. The "proper" path.
#   2. azcli   — your `az login` session. Reaches accounts.azuredatabricks.net too
#                IF you are a Databricks account admin — no SP secret needed.
#   3. profile — workspace-only PAT profile (aschwabe-$ENV). Account-level modules
#                will fail. Last resort.
#
# CI/CD (GitHub Actions) always uses the ARM credentials the workflow injects.

# Always clear stray Databricks env vars leaking from other projects (e.g. a
# DATABRICKS_CONFIG_PROFILE pointing at an unrelated profile).
unset DATABRICKS_HOST
unset DATABRICKS_TOKEN
unset DATABRICKS_CLUSTER_ID
unset DATABRICKS_CONFIG_PROFILE

# Optionally source local SP credentials (gitignored). Point SP_CREDS_FILE at a
# file, or drop one at infra/.sp-creds-$ENV.env. The Setup Wizard can emit this
# (WIZARD_EMIT_SP_ENV). Format: KEY=VALUE lines (ARM_* / DATABRICKS_AZURE_*).
SP_CREDS_FILE="${SP_CREDS_FILE:-$INFRA_DIR/.sp-creds-${ENV}.env}"
if [[ -f "$SP_CREDS_FILE" ]]; then
  echo "Sourcing SP credentials: $SP_CREDS_FILE"
  set -a; source "$SP_CREDS_FILE"; set +a
fi

# Mirror ARM_* → DATABRICKS_AZURE_* so the databricks provider can use the SP.
if [[ -n "${ARM_CLIENT_ID:-}" ]]; then
  export DATABRICKS_AZURE_CLIENT_ID="${DATABRICKS_AZURE_CLIENT_ID:-$ARM_CLIENT_ID}"
  export DATABRICKS_AZURE_TENANT_ID="${DATABRICKS_AZURE_TENANT_ID:-${ARM_TENANT_ID:-}}"
  [[ -n "${ARM_CLIENT_SECRET:-}" ]] && export DATABRICKS_AZURE_CLIENT_SECRET="${DATABRICKS_AZURE_CLIENT_SECRET:-$ARM_CLIENT_SECRET}"
fi

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  echo "Auth mode:       CI/CD (ARM credentials)"
else
  MODE="${TOFU_LOCAL_AUTH:-}"
  if [[ -z "$MODE" ]]; then
    if [[ -n "${ARM_CLIENT_ID:-}" && -n "${ARM_CLIENT_SECRET:-}" ]]; then
      MODE="sp"
    elif az account show >/dev/null 2>&1; then
      MODE="azcli"
    else
      MODE="profile"
    fi
  fi
  case "$MODE" in
    sp)
      echo "Auth mode:       Local — Service Principal (full parity with CI)"
      ;;
    azcli)
      echo "Auth mode:       Local — Azure CLI session"
      echo "   Account-level modules (AIM, workload_sp) work if your az user is a Databricks account admin."
      ;;
    profile)
      export DATABRICKS_CONFIG_PROFILE="aschwabe-${ENV}"
      echo "Auth mode:       Local — PAT profile (aschwabe-${ENV})"
      echo "⚠️  Workspace-only: account-level modules (AIM, workload_sp) will fail."
      echo "   For full local testing, set SP_CREDS_FILE (SP creds) or run 'az login'."
      ;;
  esac
fi
echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""

# Before applying, adopt the pre-registered CI/CD SP so the first apply doesn't
# fail with "already exists in this account" (idempotent; skips if not needed).
if [[ "$TOFU_CMD" == "apply" ]]; then
  maybe_import_cicd_sp
fi

# Execute OpenTofu command
eval "$FULL_CMD"

EXIT_CODE=$?

echo ""
echo "────────────────────────────────────────────────────────────────"
if [[ $EXIT_CODE -eq 0 ]]; then
  echo "✅ Command completed successfully"
else
  echo "❌ Command failed with exit code $EXIT_CODE"
fi

exit $EXIT_CODE
