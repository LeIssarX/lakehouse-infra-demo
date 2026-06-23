output "workspace_id" {
  description = "The Azure resource ID of the Databricks workspace"
  value       = local.ws_id
}

output "databricks_workspace_id" {
  description = "The Databricks workspace ID (numeric, used for Databricks provider resources)"
  value       = local.ws_workspace_id
}

output "workspace_url" {
  description = "The workspace URL (used for Databricks CLI and API)"
  value       = "https://${local.ws_url}"
}

output "workspace_name" {
  description = "The name of the Databricks workspace"
  value       = local.ws_name
}

output "managed_resource_group_id" {
  description = "The ID of the managed resource group created by Databricks"
  value       = local.ws_managed_rg_id
}

output "access_connector_id" {
  description = "The ID of the Databricks Access Connector (for Unity Catalog storage RBAC)"
  value       = azurerm_databricks_access_connector.main.id
}

output "access_connector_principal_id" {
  description = "The principal ID of the Access Connector managed identity (for role assignments)"
  value       = azurerm_databricks_access_connector.main.identity[0].principal_id
}

output "workspace_resource_id" {
  description = "The Azure resource ID of the workspace (for metastore assignment)"
  value       = local.ws_id
}

output "sku" {
  description = "The SKU of the Databricks workspace"
  value       = local.ws_sku
}
