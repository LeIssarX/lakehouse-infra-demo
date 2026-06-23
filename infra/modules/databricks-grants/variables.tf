variable "catalog_name" {
  description = "Name of the Unity Catalog catalog to apply grants to"
  type        = string
}

variable "catalog_grants" {
  description = "Map of catalog-level grant configurations. Key is an arbitrary label."
  type = map(object({
    principal  = string
    privileges = list(string)
  }))
  default = {}
}

variable "schema_grants" {
  description = "Map of schema names to their grant configurations. Outer key = schema name, inner key = arbitrary label."
  type = map(map(object({
    principal  = string
    privileges = list(string)
  })))
  default = {}
}

variable "external_location_grants" {
  description = "Map of external location names to their grant configurations. Outer key = external location name, inner key = arbitrary label."
  type = map(map(object({
    principal  = string
    privileges = list(string)
  })))
  default = {}
}

variable "system_schema_grants" {
  description = <<-EOT
    Map of system schema names to their grant configurations.
    Outer key = system schema name (e.g. "access", "billing", "lineage", "query").
    Inner key = arbitrary label, value = principal + privileges.

    Example:
      system_schema_grants = {
        access  = { stewards = { principal = "Databricks-Stewards-Prod", privileges = ["SELECT"] } }
        billing = { stewards = { principal = "Databricks-Stewards-Prod", privileges = ["SELECT"] } }
      }
  EOT
  type = map(map(object({
    principal  = string
    privileges = list(string)
  })))
  default = {}
}
