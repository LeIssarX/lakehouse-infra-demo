# ==========================================================
# Outputs
# ==========================================================

# ==========================================================
# Resource Group
# ==========================================================

output "resource_group_name" {
  description = "Name of the resource group"
  value       = local.resource_group_name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = local.resource_group_id
}

output "tags" {
  description = "Merged resource tags for injection into Databricks bundles via --var flags"
  value       = merge(var.tags, { "Environment" = var.environment })
}

# ==========================================================
# Network
# ==========================================================

output "vnet_id" {
  description = "ID of the Virtual Network (empty when VNet injection disabled)"
  value       = var.enable_vnet_injection ? module.network[0].vnet_id : ""
}

output "vnet_name" {
  description = "Name of the Virtual Network (empty when VNet injection disabled)"
  value       = var.enable_vnet_injection ? module.network[0].vnet_name : ""
}

# ==========================================================
# Databricks Workspace
# ==========================================================

output "databricks_workspace_id" {
  description = "Databricks workspace ID"
  value       = module.databricks_workspace.workspace_id
}

output "databricks_workspace_url" {
  description = "Databricks workspace URL"
  value       = module.databricks_workspace.workspace_url
}

output "databricks_access_connector_id" {
  description = "Databricks Access Connector ID (for RBAC)"
  value       = module.databricks_workspace.access_connector_id
}

# ==========================================================
# Storage
# ==========================================================

output "storage_account_names" {
  description = "Map of storage account key to Azure storage account name"
  value       = { for k, v in module.storage : k => v.storage_account_name }
}

output "storage_primary_dfs_endpoints" {
  description = "Map of storage account key to primary DFS endpoint (for Unity Catalog external locations)"
  value       = { for k, v in module.storage : k => v.primary_dfs_endpoint }
}

output "storage_container_urls" {
  description = "All container abfss:// URLs across all storage accounts (key: '{account}-{container}')"
  value       = local.all_external_locations
}

output "metastore_url" {
  description = "Unity Catalog metastore storage URL (lake account)"
  value       = local.metastore_storage_url
}

# ==========================================================
# Key Vault
# ==========================================================

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = module.key_vault.key_vault_name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = module.key_vault.key_vault_id
}

output "key_vault_uri" {
  description = "URI of the Key Vault (for Databricks secret scope)"
  value       = module.key_vault.key_vault_uri
}

# ==========================================================
# Unity Catalog
# ==========================================================

output "unity_catalog_metastore_id" {
  description = "Unity Catalog metastore ID"
  value       = module.unity_catalog.metastore_id
}

output "unity_catalog_catalog_name" {
  description = "Unity Catalog catalog name"
  value       = module.unity_catalog.catalog_name
}

output "unity_catalog_schemas" {
  description = "Map of schema names to their full names"
  value       = module.unity_catalog.schema_full_names
}

output "unity_catalog_volumes" {
  description = "Map of volume access paths"
  value       = module.unity_catalog.volume_paths
}

# ==========================================================
# Governance
# ==========================================================

output "cluster_policies" {
  description = "Map of cluster policy names to IDs"
  value       = module.governance.cluster_policy_ids
}

# ==========================================================
# Compute Outputs
# ==========================================================

output "cluster_ids" {
  description = "Map of cluster name to Databricks cluster ID"
  value       = { for k, v in module.cluster : k => v.cluster_id }
}

output "cluster_urls" {
  description = "Map of cluster name to Databricks cluster URL"
  value       = { for k, v in module.cluster : k => v.cluster_url }
}

# ==========================================================
# SQL Warehouse Outputs
# ==========================================================

output "sql_warehouse_ids" {
  description = "Map of SQL warehouse name to warehouse ID"
  value       = { for k, v in databricks_sql_endpoint.warehouses : k => v.id }
}

output "sql_warehouse_jdbc_urls" {
  description = "Map of SQL warehouse name to JDBC connection URL"
  value       = { for k, v in databricks_sql_endpoint.warehouses : k => v.jdbc_url }
  sensitive   = false
}

# ==========================================================
# Connection Information
# ==========================================================

output "databricks_cli_configure" {
  description = "Command to configure Databricks CLI"
  value       = "databricks configure --token --host ${module.databricks_workspace.workspace_url}"
}

output "databricks_secret_scope_name" {
  description = "Name of the Key Vault-backed secret scope"
  value       = databricks_secret_scope.kv_backed.name
}

output "databricks_secret_scope_backend" {
  description = "Key Vault backing the secret scope"
  value       = "${module.key_vault.key_vault_name} (${module.key_vault.key_vault_uri})"
}
