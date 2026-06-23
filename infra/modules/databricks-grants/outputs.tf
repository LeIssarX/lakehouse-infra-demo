output "catalog_grants_applied" {
  description = "Whether catalog-level grants were applied"
  value       = length(var.catalog_grants) > 0
}

output "schema_grants_applied" {
  description = "Set of schema names that had grants applied"
  value       = toset(keys(var.schema_grants))
}

output "external_location_grants_applied" {
  description = "Set of external location names that had grants applied"
  value       = toset(keys(var.external_location_grants))
}
