#!/usr/bin/env bash
# cleanup-databricks-account.sh <dev|prod> [workspace_url]
#
# Deletes stale Unity Catalog storage credentials and their dependent external
# locations before a fresh dev deployment. Safe to run multiple times: exits 0
# if the credential doesn't exist or the workspace can't be reached.
#
# DEV ONLY — exits immediately (exit 0) for any other environment.
#
# Arguments:
#   $1  environment  (required): "dev" or "prod"
#   $2  workspace_url (optional): full https://... URL — skips az lookup when provided
#                                 (Terraform passes this after creating the workspace)

set -uo pipefail

ENV="${1:-}"
WORKSPACE_URL_ARG="${2:-}"

if [[ "$ENV" != "dev" ]]; then
  echo "[INFO] cleanup-databricks-account.sh: only applicable to dev — skipping for '${ENV}'"
  exit 0
fi

# Blueprint naming conventions
WORKSPACE_NAME="dbw-lakehouse-${ENV}"
RG_NAME="rg-lakehouse-${ENV}"
CRED_NAME="lakehouse_${ENV}_credential"
# Note: CRED_NAME is also derived from var.catalog_name in Terraform, but since the
# blueprint default is "lakehouse_{env}", hardcoding here keeps the script self-contained.

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_step() { echo -e "\n${CYAN}==> $*${NC}"; }
log_info() { echo -e "${GREEN}[INFO]${NC}    $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }

# ------------------------------------------------------------------
# 1. Resolve workspace URL
# ------------------------------------------------------------------
WORKSPACE_URL=""

if [[ -n "$WORKSPACE_URL_ARG" ]]; then
  WORKSPACE_URL="$WORKSPACE_URL_ARG"
  log_info "Using provided workspace URL: $WORKSPACE_URL"
else
  log_step "Looking up Databricks workspace: $WORKSPACE_NAME (RG: $RG_NAME)"
  WORKSPACE_HOST=$(az databricks workspace show \
    --resource-group "$RG_NAME" \
    --name "$WORKSPACE_NAME" \
    --query workspaceUrl -o tsv 2>/dev/null || echo "")

  if [[ -z "$WORKSPACE_HOST" ]]; then
    log_info "Workspace '$WORKSPACE_NAME' not found in RG '$RG_NAME' — no cleanup needed"
    exit 0
  fi
  WORKSPACE_URL="https://$WORKSPACE_HOST"
  log_info "Found workspace: $WORKSPACE_URL"
fi

# ------------------------------------------------------------------
# 2. Obtain a Databricks token
# ------------------------------------------------------------------
log_step "Obtaining Databricks access token"
TOKEN=""
DATABRICKS_RESOURCE="2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"

# Try SP client credentials FIRST — same auth path the Terraform provider uses.
# Databricks workspace-local identity caches may recognize the direct client_credentials
# token with full account-admin/metastore-admin privileges, while OIDC tokens from
# 'az account get-access-token' (GitHub Actions federated identity) can be mapped with
# reduced privilege levels in a freshly-created workspace.
if [[ -n "${DATABRICKS_AZURE_CLIENT_ID:-}" ]] && \
   [[ -n "${DATABRICKS_AZURE_CLIENT_SECRET:-}" ]] && \
   [[ -n "${DATABRICKS_AZURE_TENANT_ID:-}" ]]; then
  TOKEN=$(curl -s -X POST \
    "https://login.microsoftonline.com/${DATABRICKS_AZURE_TENANT_ID}/oauth2/v2.0/token" \
    -d "grant_type=client_credentials" \
    -d "client_id=${DATABRICKS_AZURE_CLIENT_ID}" \
    -d "client_secret=${DATABRICKS_AZURE_CLIENT_SECRET}" \
    -d "scope=${DATABRICKS_RESOURCE}/.default" \
    2>/dev/null | jq -r '.access_token // empty' 2>/dev/null || echo "")
fi

# Fall back to Azure CLI session (OIDC login — wizard / local runs without secret)
if [[ -z "$TOKEN" ]]; then
  TOKEN=$(az account get-access-token \
    --resource "$DATABRICKS_RESOURCE" \
    --query accessToken -o tsv 2>/dev/null || echo "")
fi

if [[ -z "$TOKEN" ]]; then
  log_warn "Could not obtain a Databricks token — skipping cleanup"
  log_warn "If tofu apply later fails with 'storage credential already exists',"
  log_warn "delete '$CRED_NAME' manually in the Databricks account console."
  exit 0
fi
log_info "Token obtained"

# ------------------------------------------------------------------
# 3. Wait for workspace UC API to be ready
#    When called from terraform_data right after workspace creation,
#    the auto-metastore attachment can take up to ~60s to initialize.
#    Skip this wait in the pre-plan path (no workspace URL arg).
# ------------------------------------------------------------------
if [[ -n "$WORKSPACE_URL_ARG" ]]; then
  log_step "Waiting for workspace UC API to be ready (up to 120s)"
  UC_READY=false
  for i in $(seq 1 12); do
    UC_PING=$(curl -sf -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $TOKEN" \
      "${WORKSPACE_URL}/api/2.1/unity-catalog/storage-credentials" \
      2>/dev/null || echo "000")
    if [[ "$UC_PING" =~ ^2 ]]; then
      log_info "UC API ready (attempt $i, HTTP $UC_PING)"
      UC_READY=true
      break
    fi
    log_info "UC API not ready yet (HTTP $UC_PING, attempt $i/12) — waiting 10s..."
    sleep 10
  done
  if [[ "$UC_READY" != "true" ]]; then
    log_warn "UC API did not become ready within 120s — skipping credential cleanup"
    log_warn "If tofu apply fails with 'credential already exists', re-run the workflow."
    exit 0
  fi
fi

# ------------------------------------------------------------------
# 4. (removed)
#    The old "metastore-admin confirmed via credential HTTP 200" check
#    was a FALSE POSITIVE: the SP sees its own credential as owner even
#    before workspace-admin → metastore-admin propagation completes.
#    Section 5 now retries on 403 to handle that propagation window.
# ------------------------------------------------------------------

# ------------------------------------------------------------------
# 5. Delete stale external locations (lakehouse_{ENV}_*)
#
#    KNOWN ISSUES with naive approaches:
#      a) List API returns EMPTY for workspace-bound/orphaned locations
#         (bound to the old deleted workspace → invisible from new one).
#      b) Credential HTTP 200 != metastore-admin ready; SP can see its
#         OWN credential as owner BEFORE admin propagation completes,
#         causing 403 on DELETE even though admin was "confirmed".
#
#    Fix: DELETE all 8 blueprint default names directly (bypass list),
#    with a two-pass retry when 403 is returned. 403 means metastore-
#    admin hasn't propagated yet — wait 30s then try the failures again.
#    Max extra wait: 30s (one sleep, shared across all locations).
# ------------------------------------------------------------------
log_step "Deleting stale external locations: lakehouse_${ENV}_* (direct named delete, 403 retry)"

DEFAULT_CONTAINERS=("core" "curated" "landing" "mart" "metastore" "raw" "reporting" "sharing")
DELETED_LOC_COUNT=0
RETRY_LOCS=()

# Pass 1 — attempt all 8 locations WITHOUT force first.
#
#    PERMISSION MODEL: Databricks external location DELETE requires either:
#      a) ownership of the location (sufficient WITHOUT force=true)
#      b) MANAGE privilege (required WITH force=true when dependents exist)
#      c) metastore-admin (always sufficient)
#
#    The CI/CD SP is the OWNER (it created these in a prior run). Owner
#    DELETE without force works even without MANAGE. If locations have
#    dependent tables (prior successful deploy), we fall back to force=true.
#    If force=true also returns 403, the import step will handle these
#    locations by pulling them into state so tofu does UPDATE, not CREATE.
for suffix in "${DEFAULT_CONTAINERS[@]}"; do
  loc_name="lakehouse_${ENV}_${suffix}"

  # First: try without force (owner privilege is sufficient if no dependents)
  DEL_LOC=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: Bearer $TOKEN" \
    "${WORKSPACE_URL}/api/2.1/unity-catalog/external-locations/${loc_name}" \
    2>/dev/null || echo "000")

  # If no-force succeeded: done
  if [[ "$DEL_LOC" =~ ^2 ]]; then
    log_info "Deleted stale location '$loc_name' (no-force)"
    ((DELETED_LOC_COUNT++)) || true
    continue
  fi

  # If no-force returned 404: already gone
  if [[ "$DEL_LOC" == "404" ]]; then
    log_info "Location '$loc_name' not found — already clean"
    continue
  fi

  # If no-force returned 409/400: has dependent objects → try with force=true
  if [[ "$DEL_LOC" == "409" || "$DEL_LOC" == "400" ]]; then
    log_info "Location '$loc_name' has dependents (HTTP $DEL_LOC) — retrying with force=true"
    DEL_FORCE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
      -H "Authorization: Bearer $TOKEN" \
      "${WORKSPACE_URL}/api/2.1/unity-catalog/external-locations/${loc_name}?force=true" \
      2>/dev/null || echo "000")
    if [[ "$DEL_FORCE" =~ ^2 ]]; then
      log_info "Deleted stale location '$loc_name' (force=true)"
      ((DELETED_LOC_COUNT++)) || true
      continue
    elif [[ "$DEL_FORCE" == "403" ]]; then
      log_info "Location '$loc_name' returned 403 on force-delete — needs MANAGE or metastore-admin, will retry"
      RETRY_LOCS+=("$loc_name")
    else
      log_info "Could not delete '$loc_name' (no-force=$DEL_LOC, force=$DEL_FORCE)"
    fi
    continue
  fi

  # If no-force returned 403: MANAGE/metastore-admin required → retry after propagation
  if [[ "$DEL_LOC" == "403" ]]; then
    log_info "Location '$loc_name' returned 403 — will retry after 30s propagation wait"
    RETRY_LOCS+=("$loc_name")
    continue
  fi

  log_info "Could not delete '$loc_name' (HTTP $DEL_LOC)"
done

# Pass 2 — if any 403s, wait 30s for metastore-admin to propagate, then retry with force
if [[ ${#RETRY_LOCS[@]} -gt 0 ]]; then
  log_info "${#RETRY_LOCS[@]} location(s) returned 403 — waiting 30s for metastore-admin propagation..."
  sleep 30
  for loc_name in "${RETRY_LOCS[@]}"; do
    DEL_LOC=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
      -H "Authorization: Bearer $TOKEN" \
      "${WORKSPACE_URL}/api/2.1/unity-catalog/external-locations/${loc_name}?force=true" \
      2>/dev/null || echo "000")
    if [[ "$DEL_LOC" =~ ^2 ]]; then
      log_info "Deleted stale location '$loc_name' (retry, force=true)"
      ((DELETED_LOC_COUNT++)) || true
    elif [[ "$DEL_LOC" == "404" ]]; then
      log_info "Location '$loc_name' not found on retry — already clean"
    else
      log_warn "Location '$loc_name' still returned HTTP $DEL_LOC after retry — the import step will handle it via tofu state import"
    fi
  done
fi

log_info "Location cleanup complete: $DELETED_LOC_COUNT deleted"

# ------------------------------------------------------------------
# 6. Check whether the stale credential exists
# ------------------------------------------------------------------
log_step "Checking for stale storage credential: $CRED_NAME"

# Use -s (no -f) so curl never exits non-zero on HTTP errors — this keeps
# the %{http_code} output clean and prevents '|| echo "000"' from appending
# a spurious '000' to the real status code (e.g. '403000' instead of '403').
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  "${WORKSPACE_URL}/api/2.1/unity-catalog/storage-credentials/${CRED_NAME}" \
  2>/dev/null || echo "000")

if [[ "$HTTP_STATUS" != "200" ]]; then
  log_info "Storage credential '$CRED_NAME' not found (HTTP $HTTP_STATUS) — nothing to clean up"
  exit 0
fi

# ------------------------------------------------------------------
# 6. Transfer ownership to the CI/CD SP before deleting.
#    If the credential was created by a different identity (e.g. a local run
#    as the logged-in user instead of the CI/CD SP), the SP won't be the owner
#    and DELETE returns 403 even with force=true. Patching owner first works
#    if the SP has metastore-admin rights via account-admin status.
# ------------------------------------------------------------------
if [[ -n "${DATABRICKS_AZURE_CLIENT_ID:-}" ]]; then
  log_step "Transferring credential ownership to CI/CD SP (${DATABRICKS_AZURE_CLIENT_ID})"
  PATCH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"owner\": \"${DATABRICKS_AZURE_CLIENT_ID}\"}" \
    "${WORKSPACE_URL}/api/2.1/unity-catalog/storage-credentials/${CRED_NAME}" \
    2>/dev/null || echo "000")
  if [[ "$PATCH_STATUS" =~ ^2 ]]; then
    log_info "Ownership transferred (HTTP $PATCH_STATUS) — SP is now the credential owner"
    sleep 2
  else
    log_info "Ownership PATCH returned HTTP $PATCH_STATUS — SP may already be owner or lacks metastore-admin rights"
  fi
fi

# ------------------------------------------------------------------
# 7. Delete the credential (force=true cascades any remaining dependents)
#    Retry up to 10 times with 30s backoff: the CI/CD SP's workspace-admin
#    status can take a short time to propagate after the workspace assignment
#    completes. Retrying allows that window to pass.
# ------------------------------------------------------------------
log_step "Deleting stale credential '$CRED_NAME' (force=true → cascades any remaining dependents)"

DELETED=false
for i in $(seq 1 10); do
  DELETE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: Bearer $TOKEN" \
    "${WORKSPACE_URL}/api/2.1/unity-catalog/storage-credentials/${CRED_NAME}?force=true" \
    2>/dev/null || echo "000")

  if [[ "$DELETE_STATUS" =~ ^2 ]]; then
    log_info "Deleted '$CRED_NAME' and all dependent external locations (attempt $i)"
    DELETED=true
    break
  elif [[ "$DELETE_STATUS" == "403" || "$DELETE_STATUS" == "401" ]]; then
    if (( i < 10 )); then
      log_info "DELETE returned HTTP $DELETE_STATUS (attempt $i/10) — account admin may not have propagated yet, retrying in 30s..."
      sleep 30
    else
      log_warn "DELETE returned HTTP $DELETE_STATUS after 10 attempts — account admin propagation timed out"
    fi
  else
    log_warn "DELETE returned HTTP $DELETE_STATUS — credential may already be gone"
    break
  fi
done

if [[ "$DELETED" != "true" ]]; then
  log_warn "Could not delete '$CRED_NAME' — if tofu apply fails with 'already exists',"
  log_warn "remove it manually from the Databricks account console."
fi

exit 0
