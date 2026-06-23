# ==========================================================
# Module: Key Vault
# ==========================================================

module "key_vault" {
  source = "./modules/key-vault"

  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  environment         = var.environment

  key_vault_name = var.key_vault_name

  # RBAC assignments
  rbac_assignments = {
    deployer = {
      principal_id = data.azurerm_client_config.current.object_id
      role         = "Key Vault Administrator"
    }
    databricks = {
      principal_id = module.databricks_workspace.access_connector_principal_id
      role         = "Key Vault Secrets User"
    }
  }

  # Network security
  enable_public_access = var.enable_public_access
  allowed_ip_ranges    = var.key_vault_allowed_ips

  # Protection
  enable_soft_delete         = true
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  enable_purge_protection    = var.enable_purge_protection

  # Diagnostic logging (audit trail)
  enable_diagnostic_logs     = true
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  tags = var.tags
}

# ==========================================================
# Resource: RBAC Propagation Wait
# ==========================================================
# Azure RBAC is eventually consistent — propagation takes 2-5 minutes.
# This ensures Key Vault permissions are active before workload SP writes secrets.
# Reference: https://learn.microsoft.com/azure/role-based-access-control/troubleshooting

resource "time_sleep" "wait_for_rbac_propagation" {
  depends_on = [module.key_vault]

  create_duration = var.key_vault_rbac_propagation_wait

  triggers = {
    keyvault_id = module.key_vault.key_vault_id
  }
}

# ==========================================================
# Databricks Secret Scope (Key Vault-backed)
# ==========================================================

resource "databricks_secret_scope" "kv_backed" {
  provider = databricks.workspace

  name = var.key_vault_secret_scope_name

  keyvault_metadata {
    resource_id = module.key_vault.key_vault_id
    dns_name    = module.key_vault.key_vault_uri
  }

  depends_on = [
    module.key_vault,
    module.databricks_workspace
  ]
}
