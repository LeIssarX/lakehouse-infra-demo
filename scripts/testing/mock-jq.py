#!/usr/bin/env python3
"""
Mock jq for testing cleanup-databricks-account.sh.

Handles the specific jq invocations used in the cleanup script:
  1. jq -r '.access_token // empty'        ← token parsing
  2. jq -r --arg prefix "..." '[...]| .[]'  ← external location list
"""
import sys
import json

args = sys.argv[1:]
raw = "-r" in args

# Collect --arg varname value bindings
named = {}
i = 0
while i < len(args):
    if args[i] == "--arg" and i + 2 < len(args):
        named[args[i + 1]] = args[i + 2]
        i += 3
    else:
        i += 1

# Find the query (first non-flag, non-arg-value argument)
query = ""
skip_next = False
for arg in args:
    if skip_next:
        skip_next = False
        continue
    if arg in ("-r", "--rawoutput", "--raw-output", "--arg"):
        if arg == "--arg":
            skip_next = True  # skip both name and value
        continue
    if not arg.startswith("-") and not query:
        query = arg

data = sys.stdin.read().strip()
if not data:
    sys.exit(0)

try:
    obj = json.loads(data)
except Exception:
    sys.exit(0)

# Route based on query pattern
if ".access_token" in query:
    val = obj.get("access_token", "")
    print(val if raw else json.dumps(val))

elif "external_locations" in query:
    prefix = named.get("prefix", "")
    locs = obj.get("external_locations", [])
    for loc in locs:
        name = loc.get("name", "")
        if name.startswith(prefix):
            print(name if raw else json.dumps(name))
