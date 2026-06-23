# ==========================================================
# SQL Warehouses
# ==========================================================
# SQL Warehouses for analytics, BI, and SQL-based workloads.
# Each entry in var.sql_warehouses provisions a separate warehouse.
# Add or remove entries in your *.tfvars to provision/deprovision.
#
# Example:
#   sql_warehouses = {
#     "shared"    = {}
#     "analytics" = { size = "Medium" }
#   }

resource "databricks_sql_endpoint" "warehouses" {
  provider = databricks.workspace
  for_each = var.sql_warehouses

  name           = "${var.environment}-${each.key}"
  cluster_size   = each.value.size
  warehouse_type = each.value.type
  auto_stop_mins = each.value.auto_stop_mins

  enable_serverless_compute = each.value.enable_serverless

  channel {
    name = "CHANNEL_NAME_CURRENT"
  }

  tags {
    dynamic "custom_tags" {
      for_each = merge(var.tags, {
        Purpose = "sql-analytics"
        Name    = "${var.environment}-${each.key}"
      })
      content {
        key   = custom_tags.key
        value = custom_tags.value
      }
    }
  }

  depends_on = [module.unity_catalog]
}
