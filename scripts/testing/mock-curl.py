#!/usr/bin/env python3
"""
Mock curl for testing cleanup-databricks-account.sh.

Intercepts all HTTP calls made by the cleanup script and returns realistic
mock responses. Logs every request to $CURL_CALL_LOG so tests can assert
which calls were made.

Simulates the exact bug scenario:
  - List API (/unity-catalog/external-locations) returns EMPTY
  - But 4 of the 8 known locations "exist" and should be DELETEd
  - 4 others are already gone (404)
This proves the fix (direct named delete) works even when list API fails.
"""
import sys
import os
import json

# ── Parse curl arguments ───────────────────────────────────────────────────────
args = sys.argv[1:]
method = "GET"
url_raw = None
write_out = None
output_file = None

i = 0
while i < len(args):
    arg = args[i]
    if arg in ("-X", "--request"):
        i += 1
        if i < len(args):
            method = args[i]
    elif arg in ("-w", "--write-out"):
        i += 1
        if i < len(args):
            write_out = args[i]
    elif arg in ("-o", "--output"):
        i += 1
        if i < len(args):
            output_file = args[i]
    elif arg in ("-H", "--header", "-d", "--data", "--data-urlencode"):
        i += 1  # skip value
    elif arg.startswith("http"):
        url_raw = arg
    i += 1

url = url_raw.split("?")[0] if url_raw else ""

# ── Log the call ───────────────────────────────────────────────────────────────
log_file = os.environ.get("CURL_CALL_LOG", "/tmp/curl-calls.log")
with open(log_file, "a") as f:
    f.write(f"{method} {url}\n")

# ── Emit response ──────────────────────────────────────────────────────────────
def respond(body="", status=200):
    if output_file and output_file != "/dev/null":
        with open(output_file, "w") as f:
            f.write(body)
    elif not output_file:
        sys.stdout.write(body)
    # -w "%{http_code}" → emit status code to stdout (in addition to body)
    if write_out and "%{http_code}" in write_out:
        sys.stdout.write(str(status))
    sys.exit(0)

if not url:
    sys.exit(0)

# ── OAuth token endpoint ───────────────────────────────────────────────────────
if "oauth2/v2.0/token" in url:
    respond(json.dumps({"access_token": "mock-token-for-testing"}))

# ── UC API readiness probe ─────────────────────────────────────────────────────
# GET /api/2.1/unity-catalog/storage-credentials  (no credential name in path)
elif "/unity-catalog/storage-credentials" in url and "lakehouse_dev_credential" not in url and method == "GET":
    respond(status=200)

# ── Stale credential probe / ownership transfer / delete ──────────────────────
elif "/unity-catalog/storage-credentials/lakehouse_dev_credential" in url:
    if method == "GET":
        # Stale credential IS visible (metastore-admin confirmed)
        respond(json.dumps({"name": "lakehouse_dev_credential", "owner": "some-other-sp"}), 200)
    elif method == "PATCH":
        respond(json.dumps({"name": "lakehouse_dev_credential", "owner": "test-client-id"}), 200)
    elif method == "DELETE":
        respond(status=200)
    else:
        respond(status=405)

# ── External location DELETE (the fix being tested) ───────────────────────────
elif "/unity-catalog/external-locations/lakehouse_dev_" in url and method == "DELETE":
    loc_name = url.split("/external-locations/")[1].split("?")[0]

    if os.environ.get("MOCK_403_MODE") == "1":
        # Simulate the exact run 27831843333 failure: all 8 locations return 403
        # on first attempt (metastore-admin not yet propagated), then 200 on retry.
        # Uses a counter file per location (one call = 403, two+ calls = 200).
        tmp_dir = os.environ.get("TMP_DIR", "/tmp")
        counter_file = os.path.join(tmp_dir, f"count_{loc_name}.txt")
        count = 0
        if os.path.exists(counter_file):
            with open(counter_file) as f:
                count = int(f.read().strip() or "0")
        with open(counter_file, "w") as f:
            f.write(str(count + 1))
        if count == 0:
            respond(status=403)  # first attempt: admin not yet propagated
        else:
            respond(status=200)  # retry: admin propagated, location deleted
    else:
        # Default scenario: 4 locations are stale and exist → 200
        #                   4 locations are already gone → 404
        # (The old list API would return EMPTY for all of these, which was the bug)
        stale = {"lakehouse_dev_core", "lakehouse_dev_curated", "lakehouse_dev_raw", "lakehouse_dev_landing"}
        if loc_name in stale:
            respond(status=200)  # deleted
        else:
            respond(status=404)  # already clean

# ── External location LIST (the unreliable API — returns empty intentionally) ──
elif "/unity-catalog/external-locations" in url and method == "GET":
    # Simulate the bug: list returns EMPTY even though locations exist
    respond(json.dumps({"external_locations": []}), 200)

# ── Fallback ───────────────────────────────────────────────────────────────────
else:
    respond(status=404)
