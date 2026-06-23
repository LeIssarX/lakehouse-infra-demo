#!/bin/bash
# ==========================================================
# Databricks Asset Bundle Wrapper Script
# ==========================================================
# Automatically sets the correct Databricks CLI profile and
# workspace host for bundle commands, preventing accidental
# use of profiles from other projects (e.g., customer workspaces).
#
# Usage:
#   ./scripts/bundle-wrapper.sh <bundle> dev validate
#   ./scripts/bundle-wrapper.sh <bundle> dev deploy
#   ./scripts/bundle-wrapper.sh <bundle> dev run customers_pipeline
#   ./scripts/bundle-wrapper.sh <bundle> prod validate
#
# This script simplifies the command from:
#   cd bundles/example-lakeflow-pipeline
#   DATABRICKS_CONFIG_PROFILE=aschwabe-dev databricks bundle validate -t dev
#
# To:
#   ./scripts/bundle-wrapper.sh example-lakeflow-pipeline dev validate
# ==========================================================

set -euo pipefail

# ==========================================================
# Configuration — profile names per environment
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLES_DIR="$REPO_ROOT/bundles"

PROFILE_DEV="${DATABRICKS_PROFILE_DEV:-aschwabe-dev}"
PROFILE_PROD="${DATABRICKS_PROFILE_PROD:-aschwabe-prod}"

# ==========================================================
# Helper Functions
# ==========================================================

usage() {
  cat <<EOF
Usage: $0 <bundle> <environment> <bundle-command> [args...]

Automatically sets the correct Databricks CLI profile for each environment.
Prevents accidental use of unrelated profiles set in the shell environment.

Arguments:
  <bundle>          Bundle directory name under bundles/
  <environment>     Target environment (dev, prod)
  <bundle-command>  Databricks bundle command (validate, deploy, run, destroy)
  [args...]         Additional arguments passed to databricks bundle

Examples:
  $0 example-lakeflow-pipeline dev validate
  $0 example-lakeflow-pipeline dev deploy
  $0 example-lakeflow-pipeline dev run customers_pipeline
  $0 example-lakeflow-pipeline prod validate
  $0 example-lakeflow-pipeline prod deploy
  $0 example-etl-job dev validate

Profile resolution (override via env vars):
  dev  → DATABRICKS_PROFILE_DEV  (default: aschwabe-dev)
  prod → DATABRICKS_PROFILE_PROD (default: aschwabe-prod)

  export DATABRICKS_PROFILE_DEV=my-custom-dev-profile

EOF
  exit 1
}

check_requirements() {
  if ! command -v databricks &> /dev/null; then
    echo "❌ ERROR: Databricks CLI not found"
    echo ""
    echo "Install the Databricks CLI:"
    echo "  macOS:  brew install databricks/tap/databricks"
    echo "  Other:  https://docs.databricks.com/en/dev-tools/cli/install.html"
    echo ""
    exit 1
  fi
}

validate_inputs() {
  local BUNDLE=$1
  local ENV=$2

  if [[ ! -d "$BUNDLES_DIR/$BUNDLE" ]]; then
    echo "❌ ERROR: Bundle not found: bundles/$BUNDLE"
    echo ""
    echo "Available bundles:"
    for dir in "$BUNDLES_DIR"/*/; do
      if [[ -f "$dir/databricks.yml" ]]; then
        echo "  - $(basename "$dir")"
      fi
    done
    echo ""
    exit 1
  fi

  if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
    echo "❌ ERROR: Unknown environment: $ENV"
    echo "  Valid values: dev, prod"
    echo ""
    exit 1
  fi
}

# ==========================================================
# Main Script
# ==========================================================

if [[ $# -lt 3 ]]; then
  usage
fi

BUNDLE="$1"
ENV="$2"
BUNDLE_CMD="$3"
shift 3
BUNDLE_ARGS=("$@")

check_requirements
validate_inputs "$BUNDLE" "$ENV"

# Select profile based on environment
if [[ "$ENV" == "prod" ]]; then
  PROFILE="$PROFILE_PROD"
else
  PROFILE="$PROFILE_DEV"
fi

BUNDLE_DIR="$BUNDLES_DIR/$BUNDLE"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Databricks Bundle Wrapper                                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Bundle:          $BUNDLE"
echo "Environment:     $ENV"
echo "Command:         $BUNDLE_CMD ${BUNDLE_ARGS[*]:-}"
echo "Profile:         $PROFILE"
echo "Working Dir:     bundles/$BUNDLE"
echo ""

# Clear any stray Databricks env vars from other projects (e.g., customer workspaces).
# We set only the profile we explicitly chose above.
unset DATABRICKS_CONFIG_PROFILE
unset DATABRICKS_HOST
unset DATABRICKS_TOKEN
unset DATABRICKS_CLUSTER_ID

FULL_CMD="databricks bundle $BUNDLE_CMD -t $ENV ${BUNDLE_ARGS[*]:-}"

echo "Executing:"
echo "  DATABRICKS_CONFIG_PROFILE=$PROFILE $FULL_CMD"
echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""

cd "$BUNDLE_DIR"

DATABRICKS_CONFIG_PROFILE="$PROFILE" eval "$FULL_CMD"

EXIT_CODE=$?

echo ""
echo "────────────────────────────────────────────────────────────────"
if [[ $EXIT_CODE -eq 0 ]]; then
  echo "✅ Command completed successfully"
else
  echo "❌ Command failed with exit code $EXIT_CODE"
fi

exit $EXIT_CODE
