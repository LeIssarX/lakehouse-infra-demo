#!/usr/bin/env bash
# ==========================================================
# Idempotent state migration for per-resource create/existing modes
# ==========================================================
# The create-vs-existing toggles made several resources conditional (count),
# which reindexes their state addresses (foo → foo[0]). This script renames
# those state addresses so a `create`-mode plan is a no-op (no destroy/recreate).
#
# SAFE TO RUN REPEATEDLY: each move is guarded — it only runs if the un-indexed
# address still exists in state. Once migrated, every move is skipped.
#
# WHEN TO RUN: once per environment, AT THE TIME this infra code is deployed
# (i.e. in the same apply cycle that introduces the conditional resources).
# Do NOT run it while the deployed code still uses the un-indexed resources.
#
# Usage:
#   ./scripts/migrate-resource-mode-state.sh dev
#   ./scripts/migrate-resource-mode-state.sh prod
#
# Requires: tofu initialised against the target backend, and Azure auth with
# access to the remote state storage account.
set -euo pipefail

ENV="${1:-}"
if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
  echo "Usage: $0 <dev|prod>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/../infra" && pwd)"
cd "$INFRA_DIR"

echo "▶ Ensuring backend is initialised for $ENV..."
tofu init -backend-config="envs/$ENV/backend.hcl" -reconfigure >/dev/null

# Snapshot current state addresses once (fast; avoids N×state-list calls).
STATE_LIST="$(tofu state list)"

move() {
  local src="$1" dst="$2"
  if grep -qxF "$src" <<<"$STATE_LIST"; then
    echo "  mv  $src → $dst"
    tofu state mv "$src" "$dst"
  else
    echo "  ok  $src already migrated (or absent) — skipping"
  fi
}

echo "▶ Resource group"
move 'azurerm_resource_group.main' 'azurerm_resource_group.main[0]'

echo "▶ Storage (lake) account + random suffix"
move 'module.storage["lake"].azurerm_storage_account.main' 'module.storage["lake"].azurerm_storage_account.main[0]'
move 'module.storage["lake"].random_string.storage_suffix' 'module.storage["lake"].random_string.storage_suffix[0]'

echo "▶ Databricks workspace"
move 'module.databricks_workspace.azurerm_databricks_workspace.main' \
     'module.databricks_workspace.azurerm_databricks_workspace.main[0]'

echo "▶ VNet module (only present when enable_vnet_injection = true)"
for r in \
  azurerm_virtual_network.main \
  azurerm_network_security_group.main \
  azurerm_route_table.main \
  azurerm_subnet.public \
  azurerm_subnet.private \
  azurerm_subnet_network_security_group_association.public \
  azurerm_subnet_network_security_group_association.private \
  azurerm_subnet_route_table_association.public \
  azurerm_subnet_route_table_association.private; do
  move "module.network[0].$r" "module.network[0].$r[0]"
done

echo "✅ State migration complete for $ENV."
echo "   Next: run a 'tofu plan' (or the deploy workflow) and confirm there is"
echo "   NO destroy/recreate for these resources — only state addresses moved."
