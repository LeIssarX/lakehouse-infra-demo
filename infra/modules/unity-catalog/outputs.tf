output "metastore_id" {
  description = "Unity Catalog metastore ID"
  value       = local.metastore_id
}

output "catalog_id" {
  description = "Catalog ID"
  value       = databricks_catalog.this.id
}

output "catalog_name" {
  description = "Catalog name"
  value       = databricks_catalog.this.name
}

output "storage_credential_id" {
  description = "Storage credential ID"
  value       = databricks_storage_credential.external.id
}

output "storage_credential_name" {
  description = "Storage credential name"
  value       = databricks_storage_credential.external.name
}

output "external_location_ids" {
  description = "Map of external location names to their IDs"
  value       = { for k, v in databricks_external_location.locations : k => v.id }
}

output "external_location_urls" {
  description = "Map of external location names to their storage URLs"
  value       = { for k, v in databricks_external_location.locations : k => v.url }
}

output "schema_ids" {
  description = "Map of schema names to their IDs"
  value       = { for k, v in databricks_schema.schemas : k => v.id }
}

output "schema_full_names" {
  description = "Map of schema names to their fully qualified names (catalog.schema)"
  value       = { for k, v in databricks_schema.schemas : k => "${databricks_catalog.this.name}.${v.name}" }
}

output "volume_ids" {
  description = "Map of volume keys to their IDs"
  value       = { for k, v in databricks_volume.volumes : k => v.id }
}

output "volume_paths" {
  description = "Map of volume keys to their access paths (/Volumes/catalog/schema/volume)"
  value       = { for k, v in databricks_volume.volumes : k => "/Volumes/${databricks_catalog.this.name}/${v.schema_name}/${v.name}" }
}
