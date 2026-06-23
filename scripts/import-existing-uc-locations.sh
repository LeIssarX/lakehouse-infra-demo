#!/usr/bin/env bash
# import-existing-uc-locations.sh <dev|prod>
#
# Safety-net: imports stale Unity Catalog external locations into the OpenTofu
# state BEFORE plan/apply so that `tofu apply` sees them as managed resources
# rather than trying to CREATE them (which fails with "already exists").
#
# This is idempotent and a pure no-op when:
#   - The Databricks workspace does not yet exist (greenfield, pre-apply)
#   - No stale locations exist in the metastore
#   - All existing locations are already tracked in tofu state
#
# Must be run from the infra/ directory after `tofu init` (state is available).
# Env vars: ARM_*, DATABRICKS_AZURE_* (same as used in tofu plan/apply steps).

set -uo pipefail

ENV="${1:-}"
if [[ -z "$ENV" ]]; then
  echo "[ERROR] Usage: $0 <dev|prod>"
  exit 1
fi

# ------------------------------------------------------------------
# 1. Resolve Databricks workspace URL
#    Try tofu state output first (workspace already exists in state from
#    a prior partial apply). Fall back to az CLI lookup.
# ------------------------------------------------------------------
WORKSPACE_URL=""

WORKSPACE_URL=$(tofu output -raw databricks_workspace_url 2>/dev/null || echo "")

if [[ -z "$WORKSPACE_URL" ]]; then
  WORKSPACE_NAME="dbw-lakehouse-${ENV}"
  RG_NAME="rg-lakehouse-${ENV}"
  WORKSPACE_HOST=$(az databricks workspace show \
    --resource-group "$RG_NAME" \
    --name "$WORKSPACE_NAME" \
    --query workspaceUrl -o tsv 2>/dev/null || echo "")
  if [[ -n "$WORKSPACE_HOST" && "$WORKSPACE_HOST" != "None" ]]; then
    WORKSPACE_URL="https://$WORKSPACE_HOST"
  fi
fi

if [[ -z "$WORKSPACE_URL" ]]; then
  echo "[INFO] No Databricks workspace found — nothing to import. Skipping."
  exit 0
fi

echo "[INFO] Checking for untracked UC external locations in: $WORKSPACE_URL"

# ------------------------------------------------------------------
# 2. Build tofu var-file arguments (same as plan/apply steps)
# ------------------------------------------------------------------
VAR_ARGS=("-var-file=common.tfvars")
for f in "envs/${ENV}/"*.tfvars; do
  [[ -f "$f" ]] && VAR_ARGS+=("-var-file=$f")
done

# ------------------------------------------------------------------
# 3. Import blueprint default external locations DIRECTLY by name.
#
#    ROOT CAUSE: The list API (/unity-catalog/external-locations)
#    returns EMPTY for locations that are workspace-bound to an old
#    (deleted) workspace, even when the SP has full metastore access.
#    Importing by name uses GET /{name} directly, which bypasses the
#    workspace-visibility filter and works at the metastore level.
#
#    If a location doesn't exist → tofu import exits 1 → graceful skip
#    If already in state → skip
#    If exists but not in state → import so tofu UPDATE instead of CREATE
#
#    After import + credential re-creation (same name), tofu plan sees:
#      - credential: not in state → CREATE
#      - locations: in state, credential_name matches config → NO CHANGE
#    Apply creates the credential; orphaned locations reference it by
#    name → they become valid again without any DELETE needed.
#
#    Naming convention (blueprint default):
#      location name  "lakehouse_{ENV}_{container}"  e.g. "lakehouse_dev_core"
#      tofu key       "lake-{container}"              e.g. "lake-core"
# ------------------------------------------------------------------
PREFIX="lakehouse_${ENV}_"
DEFAULT_CONTAINERS=("core" "curated" "landing" "mart" "metastore" "raw" "reporting" "sharing")
IMPORTED=0
SKIPPED=0

# Get all external_location resource addresses currently in state
STATE_LOCS=$(tofu state list 2>/dev/null | grep 'databricks_external_location\.locations\[' || echo "")

echo "[INFO] Attempting direct-by-name import for ${#DEFAULT_CONTAINERS[@]} blueprint locations (bypasses list API)..."

for container in "${DEFAULT_CONTAINERS[@]}"; do
  loc_name="${PREFIX}${container}"
  tofu_key="lake-${container}"
  resource_addr="module.unity_catalog.databricks_external_location.locations[\"${tofu_key}\"]"

  # Skip if already in state
  if echo "$STATE_LOCS" | grep -qF "\"${tofu_key}\""; then
    echo "[INFO] Already in state: ${loc_name} — skipping"
    ((SKIPPED++)) || true
    continue
  fi

  # Attempt import — if location doesn't exist in metastore, tofu import exits 1 → skip
  echo "[INFO] Importing: ${loc_name} → ${resource_addr}"
  IMPORT_OUT=$(tofu import "${VAR_ARGS[@]}" "$resource_addr" "$loc_name" 2>&1) && {
    echo "[OK]   Imported ${loc_name} — tofu will UPDATE this location instead of re-creating it"
    ((IMPORTED++)) || true
  } || {
    # Exit 1 is expected when location doesn't exist (404). Only show output if unusual.
    if echo "$IMPORT_OUT" | grep -qi "error\|403\|permission\|denied"; then
      echo "[WARN] Import of ${loc_name} failed (may need manual attention):"
      echo "$IMPORT_OUT" | grep -i "error\|403\|permission\|denied" | head -5
    else
      echo "[INFO] ${loc_name} not present in metastore — will be created fresh by tofu apply"
    fi
  }
done

echo "[INFO] Import complete: ${IMPORTED} imported, ${SKIPPED} already in state."
exit 0
