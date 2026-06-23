#!/usr/bin/env bash
# ==========================================================
# Test: cleanup-databricks-account.sh — direct named delete
# ==========================================================
#
# Verifies that the cleanup script DELETEs all 8 known external location
# names DIRECTLY (not via list API), which is the fix for the persistent
# "External Location already exists" CI failure.
#
# Bug reproduced: The Databricks list API returns EMPTY for locations that
# are workspace-bound to an old (deleted) workspace. The old code relied on
# the list → it never deleted the orphaned locations → tofu apply failed.
#
# This test uses a mock curl that simulates EXACTLY that broken scenario:
#   - List API returns empty (bug scenario)
#   - 4 of the 8 known locations exist (DELETE returns 200)
#   - 4 of the 8 are already gone (DELETE returns 404)
#
# Expected: All 8 DELETE requests are sent regardless of list API result.
#
# Usage: ./scripts/testing/test-cleanup-databricks-account.sh
# Exit code: 0 = all assertions pass, 1 = one or more failures

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/../cleanup-databricks-account.sh"
MOCK_CURL="$SCRIPT_DIR/mock-curl.py"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
FAILURES=0

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; ((FAILURES++)) || true; }
section() { echo -e "\n${CYAN}==> $*${NC}"; }

# ── Pre-flight checks ──────────────────────────────────────────────────────────
if [[ ! -f "$CLEANUP_SCRIPT" ]]; then
  echo -e "${RED}ERROR:${NC} cleanup script not found: $CLEANUP_SCRIPT"
  exit 1
fi
if [[ ! -f "$MOCK_CURL" ]]; then
  echo -e "${RED}ERROR:${NC} mock curl not found: $MOCK_CURL"
  exit 1
fi
if ! command -v python3 &>/dev/null; then
  echo -e "${RED}ERROR:${NC} python3 is required to run the mock curl"
  exit 1
fi

# ── Setup ──────────────────────────────────────────────────────────────────────
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

CALL_LOG="$TMP/curl-calls.log"
touch "$CALL_LOG"

# Create a mock curl wrapper that calls the Python mock
cat > "$TMP/curl" << EOF
#!/usr/bin/env bash
TMP_DIR="$TMP" CURL_CALL_LOG="$CALL_LOG" python3 "$MOCK_CURL" "\$@"
EOF
chmod +x "$TMP/curl"

# Create a no-op sleep mock so the 30s retry wait doesn't slow down tests
cat > "$TMP/sleep" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/sleep"

# Create a mock jq so the test works even when jq is not installed locally.
# Handles the two patterns the cleanup script uses: .access_token and external_locations.
MOCK_JQ="$SCRIPT_DIR/mock-jq.py"
cat > "$TMP/jq" << EOF
#!/usr/bin/env bash
python3 "$MOCK_JQ" "\$@"
EOF
chmod +x "$TMP/jq"

# Also mock 'az' so the script never tries a real Azure CLI call
cat > "$TMP/az" << 'EOF'
#!/usr/bin/env bash
# Mock az: workspace not found (cleanup takes the "workspace URL provided" path instead)
exit 1
EOF
chmod +x "$TMP/az"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Test: cleanup-databricks-account.sh — direct named delete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " Scenario: List API returns EMPTY (orphaned/workspace-bound locations)"
echo "           Script must still DELETE all 8 known locations by name."
echo ""

# ── Run the cleanup script ─────────────────────────────────────────────────────
section "Running cleanup script (mock HTTP — no real Azure calls)"

SCRIPT_OUTPUT=$(\
  PATH="$TMP:$PATH" \
  CURL_CALL_LOG="$CALL_LOG" \
  DATABRICKS_AZURE_CLIENT_ID="test-client-id" \
  DATABRICKS_AZURE_CLIENT_SECRET="test-client-secret" \
  DATABRICKS_AZURE_TENANT_ID="test-tenant-id" \
  bash "$CLEANUP_SCRIPT" dev "https://adb-fake-12345.14.azuredatabricks.net" 2>&1 \
)

echo "$SCRIPT_OUTPUT" | grep -E "^\[|^==>|Deleted|not found|already clean|already clean|Direct named" | head -30 || true

# ── Assert: DELETE sent for all 8 known locations ──────────────────────────────
section "Assert: DELETE requests sent for all 8 known location names"

KNOWN_CONTAINERS=("core" "curated" "landing" "mart" "metastore" "raw" "reporting" "sharing")
for suffix in "${KNOWN_CONTAINERS[@]}"; do
  loc="lakehouse_dev_${suffix}"
  if grep -qF "DELETE https://adb-fake-12345.14.azuredatabricks.net/api/2.1/unity-catalog/external-locations/${loc}" "$CALL_LOG"; then
    pass "DELETE sent for '$loc'"
  else
    fail "DELETE NOT sent for '$loc'"
  fi
done

# ── Assert: Script handled 404 gracefully (no crash) ──────────────────────────
section "Assert: Script handled 404 (already clean) without crashing"

if echo "$SCRIPT_OUTPUT" | grep -q "already clean"; then
  pass "404 responses reported as 'already clean'"
else
  fail "404 responses not handled gracefully — output: $SCRIPT_OUTPUT"
fi

# ── Assert: Script handled 200 (deleted) correctly ────────────────────────────
section "Assert: Script reported successful deletes (200)"

if echo "$SCRIPT_OUTPUT" | grep -q "Deleted stale location"; then
  pass "200 responses reported as 'Deleted stale location'"
else
  fail "200 responses not recognized as successful deletes"
fi

# ── Assert: Credential was also cleaned up ────────────────────────────────────
section "Assert: Stale storage credential deleted"

if grep -qF "DELETE https://adb-fake-12345.14.azuredatabricks.net/api/2.1/unity-catalog/storage-credentials/lakehouse_dev_credential" "$CALL_LOG"; then
  pass "DELETE sent for storage credential 'lakehouse_dev_credential'"
else
  fail "DELETE NOT sent for storage credential"
fi

# ── Assert: List API was NOT the source of truth ──────────────────────────────
section "Assert: List API returned empty but deletes still happened"

if grep -qF "GET https://adb-fake-12345.14.azuredatabricks.net/api/2.1/unity-catalog/external-locations" "$CALL_LOG" 2>/dev/null; then
  echo -e "  ${YELLOW}NOTE${NC}: List API was called (optional belt-and-suspenders). This is acceptable."
fi

# This is the key assertion: even though list returned [], deletes still happened
DELETED_COUNT=$(grep -cF "DELETE https://adb-fake-12345.14.azuredatabricks.net/api/2.1/unity-catalog/external-locations/" "$CALL_LOG" 2>/dev/null) || DELETED_COUNT=0
DELETED_COUNT="${DELETED_COUNT:-0}"
if [[ "$DELETED_COUNT" -eq 8 ]]; then
  pass "All 8 location DELETE requests sent despite empty list API response"
elif [[ "$DELETED_COUNT" -gt 0 ]]; then
  fail "Only $DELETED_COUNT of 8 location DELETE requests sent"
else
  fail "No location DELETE requests were sent at all"
fi

# ── Scenario 2: 403 retry (run 27831843333 regression) ───────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Scenario 2: All 8 locations return 403 on pass 1"
echo "             (metastore-admin still propagating — run 27831843333)"
echo "             Script must retry after 30s wait and succeed on pass 2."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CALL_LOG2="$TMP/curl-calls-2.log"
touch "$CALL_LOG2"

cat > "$TMP/curl" << EOF
#!/usr/bin/env bash
TMP_DIR="$TMP" CURL_CALL_LOG="$CALL_LOG2" MOCK_403_MODE=1 python3 "$MOCK_CURL" "\$@"
EOF
chmod +x "$TMP/curl"

section "Running cleanup script with 403-first-then-200 mock"

SCRIPT_OUTPUT2=$(\
  PATH="$TMP:$PATH" \
  CURL_CALL_LOG="$CALL_LOG2" \
  DATABRICKS_AZURE_CLIENT_ID="test-client-id" \
  DATABRICKS_AZURE_CLIENT_SECRET="test-client-secret" \
  DATABRICKS_AZURE_TENANT_ID="test-tenant-id" \
  bash "$CLEANUP_SCRIPT" dev "https://adb-fake-12345.14.azuredatabricks.net" 2>&1 \
)

echo "$SCRIPT_OUTPUT2" | grep -E "^\[|^==>|403|retry|propagat|Deleted|deleted|clean" | head -40 || true

section "Assert: Script retried 403 locations (each DELETE called twice)"

for suffix in "${KNOWN_CONTAINERS[@]}"; do
  loc="lakehouse_dev_${suffix}"
  COUNT=$(grep -cF "DELETE https://adb-fake-12345.14.azuredatabricks.net/api/2.1/unity-catalog/external-locations/${loc}" "$CALL_LOG2" 2>/dev/null) || COUNT=0
  if [[ "$COUNT" -ge 2 ]]; then
    pass "DELETE retried for '$loc' ($COUNT calls)"
  else
    fail "DELETE only called $COUNT time(s) for '$loc' — retry not triggered"
  fi
done

section "Assert: Retry was logged with metastore-admin explanation"

if echo "$SCRIPT_OUTPUT2" | grep -q "403"; then
  pass "403 responses triggered retry message"
else
  fail "No mention of 403 in output — retry logic may not have run"
fi

section "Assert: All 8 locations deleted on retry (200 on pass 2)"

if echo "$SCRIPT_OUTPUT2" | grep -q "retry"; then
  pass "Retry pass logged in output"
else
  fail "No 'retry' in output — two-pass logic not triggered"
fi

DELETED2_COUNT=$(grep -cF "DELETE https://adb-fake-12345.14.azuredatabricks.net/api/2.1/unity-catalog/external-locations/" "$CALL_LOG2" 2>/dev/null) || DELETED2_COUNT=0
if [[ "$DELETED2_COUNT" -eq 16 ]]; then
  pass "16 DELETE calls total (8 pass-1 × 403 + 8 pass-2 × 200)"
else
  fail "Expected 16 DELETE calls, got $DELETED2_COUNT (8 per pass × 2 passes)"
fi

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAILURES -eq 0 ]]; then
  echo -e " ${GREEN}✅ All assertions passed${NC}"
  echo ""
  echo " Both scenarios verified:"
  echo "   1. Direct named delete bypasses unreliable list API"
  echo "   2. 403 retry handles metastore-admin propagation delay"
else
  echo -e " ${RED}❌ $FAILURES assertion(s) failed${NC}"
fi

echo ""
echo " Scenario 1 request log:"
cat "$CALL_LOG"
echo ""
echo " Scenario 2 request log:"
cat "$CALL_LOG2"
echo ""

exit $FAILURES
