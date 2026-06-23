output "storage_account_id" {
  description = "ID of the storage account"
  value       = local.account_id
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = local.account_name
}

output "primary_dfs_endpoint" {
  description = "Primary DFS endpoint for ADLS Gen2 (for Unity Catalog external locations)"
  value       = local.account_dfs_endpoint
}

output "primary_dfs_host" {
  description = "Primary DFS host (for constructing abfss:// URLs)"
  value       = local.account_dfs_host
}

output "containers" {
  description = "Map of container names to their IDs"
  value = {
    for k, v in azurerm_storage_container.containers : k => v.id
  }
}

output "container_names" {
  description = "List of container names created"
  value       = [for c in azurerm_storage_container.containers : c.name]
}

output "metastore_url" {
  description = "Unity Catalog metastore URL (abfss format) - use the 'metastore' container"
  value       = "abfss://metastore@${local.account_name}.dfs.core.windows.net/"
}

output "container_urls" {
  description = "Map of container names to their abfss:// URLs (for Unity Catalog external locations)"
  value = {
    for name in var.containers :
    name => "abfss://${name}@${local.account_name}.dfs.core.windows.net/"
  }
}

# Legacy outputs (deprecated — use container_urls map instead)
output "bronze_url" {
  description = "DEPRECATED: Use container_urls[\"bronze\"] instead"
  value       = contains(var.containers, "bronze") ? "abfss://bronze@${local.account_name}.dfs.core.windows.net/" : null
}

output "silver_url" {
  description = "DEPRECATED: Use container_urls[\"silver\"] instead"
  value       = contains(var.containers, "silver") ? "abfss://silver@${local.account_name}.dfs.core.windows.net/" : null
}

output "gold_url" {
  description = "DEPRECATED: Use container_urls[\"gold\"] instead"
  value       = contains(var.containers, "gold") ? "abfss://gold@${local.account_name}.dfs.core.windows.net/" : null
}
