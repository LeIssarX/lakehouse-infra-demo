# ==========================================================
# Databricks Grants Module
# ==========================================================
# Manages Unity Catalog permissions independently from the catalog/schema
# provisioning in databricks-governance. This separation allows permission
# changes without touching catalog infrastructure resources.
#
# Caller must pass a workspace-scoped Databricks provider via:
#   providers = { databricks = databricks.workspace }

# ==========================================================
# Catalog-Level Grants
# ==========================================================

resource "databricks_grants" "catalog" {
  count = length(var.catalog_grants) > 0 ? 1 : 0

  catalog = var.catalog_name

  dynamic "grant" {
    for_each = var.catalog_grants
    content {
      principal  = grant.value.principal
      privileges = grant.value.privileges
    }
  }
}

# ==========================================================
# Schema-Level Grants
# ==========================================================

resource "databricks_grants" "schemas" {
  for_each = var.schema_grants

  schema = "${var.catalog_name}.${each.key}"

  dynamic "grant" {
    for_each = each.value
    content {
      principal  = grant.value.principal
      privileges = grant.value.privileges
    }
  }
}

# ==========================================================
# External Location Grants
# ==========================================================

resource "databricks_grants" "external_locations" {
  for_each = var.external_location_grants

  external_location = each.key

  dynamic "grant" {
    for_each = each.value
    content {
      principal  = grant.value.principal
      privileges = grant.value.privileges
    }
  }
}

# ==========================================================
# System Schema Grants (system.access, system.billing, etc.)
# ==========================================================

resource "databricks_grants" "system_schemas" {
  for_each = var.system_schema_grants

  schema = "system.${each.key}"

  dynamic "grant" {
    for_each = each.value
    content {
      principal  = grant.value.principal
      privileges = grant.value.privileges
    }
  }
}
