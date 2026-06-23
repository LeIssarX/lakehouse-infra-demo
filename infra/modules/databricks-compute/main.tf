# ==========================================================
# Databricks Compute Module
# ==========================================================
# Provisions a single interactive cluster.
# Use for_each in the calling module to provision multiple clusters.
#
# Caller must pass a workspace-scoped Databricks provider via:
#   providers = { databricks = databricks.workspace }

# ==========================================================
# Spark runtime resolution
# ==========================================================
# databricks_cluster.spark_version needs a concrete runtime (e.g. 15.4.x-scala2.12),
# but the wizard offers "auto:*" aliases. Resolve those to the live latest runtime
# via the workspace; pass any other value (a concrete version) through unchanged.

data "databricks_spark_version" "lts" {
  long_term_support = true
}

data "databricks_spark_version" "latest" {
  latest = true
}

data "databricks_spark_version" "ml_lts" {
  long_term_support = true
  ml                = true
}

locals {
  spark_version_aliases = {
    "auto:latest-lts" = data.databricks_spark_version.lts.id
    "auto:latest"     = data.databricks_spark_version.latest.id
    "auto:latest-ml"  = data.databricks_spark_version.ml_lts.id
  }
  spark_version = lookup(local.spark_version_aliases, var.spark_version, var.spark_version)
}

# ==========================================================
# Interactive Cluster (single-user, autoscaling)
# ==========================================================

resource "databricks_cluster" "this" {
  cluster_name            = "${var.environment}-${var.name}"
  spark_version           = local.spark_version
  node_type_id            = var.node_type
  driver_node_type_id     = var.node_type
  policy_id               = var.cluster_policy_id
  data_security_mode      = var.data_security_mode
  single_user_name        = var.owner
  autotermination_minutes = var.auto_termination_minutes
  runtime_engine          = var.runtime_engine

  autoscale {
    min_workers = var.min_workers
    max_workers = var.max_workers
  }

  azure_attributes {
    availability       = var.enable_spot_instances ? "SPOT_WITH_FALLBACK_AZURE" : "ON_DEMAND_AZURE"
    spot_bid_max_price = -1
  }

  custom_tags = merge(var.tags, {
    Purpose = "development"
  })
}
