# ==========================================================
# Databricks Governance Module
# ==========================================================

# Note: This module requires workspace-level Databricks provider configuration

locals {
  # Build node type restrictions
  node_type_policy = length(var.allowed_node_types) > 0 ? {
    type   = "allowlist"
    values = var.allowed_node_types
    } : {
    type   = "unlimited"
    values = []
  }

  # Common policy settings
  common_policy_base = {
    # Unity Catalog enforcement
    "data_security_mode" = var.require_unity_catalog ? {
      type  = "fixed"
      value = "SINGLE_USER" # Required for Unity Catalog
      } : {
      type = "unlimited"
    }

    # Spark version
    "spark_version" = {
      type         = "unlimited"
      defaultValue = var.spark_version
    }

    # Node type restrictions
    "node_type_id" = local.node_type_policy

    # Auto-termination
    "autotermination_minutes" = {
      type         = "range"
      minValue     = var.autotermination_min_floor
      maxValue     = var.auto_termination_minutes
      defaultValue = var.auto_termination_minutes
    }
  }

  # Azure-specific settings
  azure_attributes = {
    "azure_attributes.availability" = var.enable_spot_instances ? {
      type  = "fixed"
      value = "SPOT_WITH_FALLBACK_AZURE" # Spot with on-demand fallback
      } : {
      type  = "fixed"
      value = "ON_DEMAND_AZURE"
    }

    "azure_attributes.spot_bid_max_price" = var.enable_spot_instances ? {
      type  = "fixed"
      value = -1 # Use on-demand price as max
    } : null
  }
}

# ==========================================================
# Cluster Policy: Shared Interactive (Dev/Exploration)
# ==========================================================

resource "databricks_cluster_policy" "shared_interactive" {
  count = var.enable_cluster_policies ? 1 : 0

  name = "${var.environment}_shared_interactive"
  definition = jsonencode(merge(
    local.common_policy_base,
    local.azure_attributes,
    {
      # Max cluster size
      "autoscale.max_workers" = var.max_workers_limit != null ? {
        type     = "range"
        maxValue = var.max_workers_limit
        } : {
        type = "unlimited"
      }

      # Driver node (can be different from worker)
      "driver_node_type_id" = local.node_type_policy

      # Runtime engine
      "runtime_engine" = {
        type         = "unlimited"
        defaultValue = "STANDARD"
      }

      # Single user mode (Unity Catalog compatible)
      "single_user_name" = {
        type  = "fixed"
        value = "{{user.email}}" # User's email
      }
    }
  ))

  # Customization: Add detailed description for users
  # Uncomment and expand with:
  # - When to use this policy (interactive exploration, notebooks)
  # - Cost guidelines (estimated $ per hour)
  # - Best practices (right-sizing, auto-termination)
  # description = "Policy for shared interactive clusters. Use for: data exploration, notebook development, ad-hoc analysis. Auto-terminates after ${var.auto_termination_minutes} min. Max ${max_clusters_per_user} clusters per user."

  max_clusters_per_user = var.interactive_max_clusters_per_user
}

# ==========================================================
# Cluster Policy: Job Clusters (Production Workloads)
# ==========================================================

resource "databricks_cluster_policy" "job_clusters" {
  count = var.enable_cluster_policies ? 1 : 0

  name = "${var.environment}_job_clusters"
  definition = jsonencode(merge(
    local.common_policy_base,
    local.azure_attributes,
    {
      # Autoscaling for jobs
      "autoscale.min_workers" = {
        type         = "range"
        minValue     = 1
        defaultValue = 1
      }

      "autoscale.max_workers" = var.max_workers_limit != null ? {
        type     = "range"
        maxValue = var.max_workers_limit
        } : {
        type = "unlimited"
      }

      # Job cluster settings
      "cluster_type" = {
        type  = "fixed"
        value = "job"
      }

      # Aggressive auto-termination for jobs
      "autotermination_minutes" = {
        type  = "fixed"
        value = var.job_autotermination_minutes
      }

      # Photon engine (recommended for SQL/Delta workloads)
      "runtime_engine" = {
        type         = "unlimited"
        defaultValue = "PHOTON"
      }
    }
  ))

  # FIXME: Update description
  # description = "Policy for production job clusters with spot instances and photon enabled"

  max_clusters_per_user = var.job_max_clusters_per_user
}

# ==========================================================
# Cluster Policy: ML Workloads
# ==========================================================

resource "databricks_cluster_policy" "ml_clusters" {
  count = var.enable_cluster_policies ? 1 : 0

  name = "${var.environment}_ml_clusters"
  definition = jsonencode(merge(
    local.common_policy_base,
    {
      # ML runtime
      "spark_version" = {
        type         = "regex"
        pattern      = ".*-ml-.*" # ML runtimes only
        defaultValue = var.ml_spark_version
      }

      # Larger nodes for ML workloads
      "node_type_id" = {
        type   = "allowlist"
        values = var.ml_allowed_node_types
        # ML/AI Workloads: Uncomment GPU nodes for deep learning and add to ml_allowed_node_types:
        # "Standard_NC6s_v3"   1x V100 GPU  | "Standard_NC12s_v3"  2x V100 | "Standard_NC24s_v3"  4x V100
      }

      # ML-specific settings
      "enable_elastic_disk" = {
        type  = "fixed"
        value = true
      }

      # Allow longer runtime for training jobs
      "autotermination_minutes" = {
        type         = "range"
        minValue     = var.ml_autotermination_min
        maxValue     = var.ml_autotermination_max
        defaultValue = var.ml_autotermination_default
      }
    }
  ))

  max_clusters_per_user = var.ml_max_clusters_per_user
}

# ==========================================================
# Cluster Policy: Lakeflow Pipelines (DLT/Streaming)
# ==========================================================

resource "databricks_cluster_policy" "lakeflow_pipelines" {
  count = var.enable_cluster_policies ? 1 : 0

  name = "${var.environment}_lakeflow_pipelines"
  definition = jsonencode(merge(
    local.common_policy_base,
    {
      # Pipeline-optimized settings
      "runtime_engine" = {
        type  = "fixed"
        value = "PHOTON" # Best for Lakeflow
      }

      # Enhanced autoscaling for streaming
      "autoscale.min_workers" = {
        type         = "range"
        minValue     = 1
        defaultValue = 2
      }

      "autoscale.max_workers" = {
        type         = "range"
        maxValue     = var.max_workers_limit != null ? var.max_workers_limit : var.pipeline_max_workers
        defaultValue = var.pipeline_max_workers
      }

      # Streaming-specific settings
      "spark_conf.spark.databricks.delta.preview.enabled" = {
        type  = "fixed"
        value = "true"
      }

      # Note: Lakeflow/DLT manages clusters automatically
      # This policy applies to underlying compute
    }
  ))

  # Customization: Add description for Lakeflow users
  # Uncomment and customize:
  # description = "Policy for Lakeflow/Delta Live Tables pipelines. Photon-accelerated, optimized for streaming workloads. Compute managed automatically by DLT."
}

# ==========================================================
# Token Management Policy
# ==========================================================

resource "databricks_workspace_conf" "token_policy" {
  count = var.enable_token_policy ? 1 : 0

  custom_config = {
    # Max token lifetime
    "maxTokenLifetimeDays" = tostring(var.max_token_lifetime_days)

    # Multi-Factor Authentication for Tokens
    # Requires: OAuth 2.0 setup with Azure AD (see docs/aim-setup.md)
    # Uncomment after OAuth configuration:
    # "enableTokensConfig" = "true"  # Requires MFA for PAT generation
  }
}

# ==========================================================
# IP Access Lists
# ==========================================================

# Allow list
resource "databricks_ip_access_list" "allowed" {
  for_each = var.enable_ip_access_lists && length(var.allowed_ip_ranges) > 0 ? toset(["allowed"]) : []

  label        = "${var.environment}_allowed_ips"
  list_type    = "ALLOW"
  ip_addresses = var.allowed_ip_ranges
  enabled      = true
}

# Block list
resource "databricks_ip_access_list" "blocked" {
  for_each = var.enable_ip_access_lists && length(var.blocked_ip_ranges) > 0 ? toset(["blocked"]) : []

  label        = "${var.environment}_blocked_ips"
  list_type    = "BLOCK"
  ip_addresses = var.blocked_ip_ranges
  enabled      = true
}

# ==========================================================
# Automatic Cluster Updates Configuration
# ==========================================================

resource "databricks_automatic_cluster_update_workspace_setting" "this" {
  count = var.enable_automatic_cluster_updates ? 1 : 0

  automatic_cluster_update_workspace {
    enabled                              = true
    restart_even_if_no_updates_available = false # Only restart if updates are available

    maintenance_window {
      week_day_based_schedule {
        frequency   = var.automatic_cluster_update_schedule.frequency
        day_of_week = var.automatic_cluster_update_schedule.day_of_week
        window_start_time {
          hours   = var.automatic_cluster_update_schedule.hour
          minutes = var.automatic_cluster_update_schedule.minute
        }
      }
    }
  }
}

# ==========================================================
# Enhanced Security Monitoring (Premium tier only)
# ==========================================================

# Note: Enhanced security is configured during workspace creation
# This feature is not available in all Databricks versions/regions
# Disabled by default to prevent deployment errors

# resource "databricks_workspace_conf" "enhanced_security" {
#   count = var.enable_enhanced_security ? 1 : 0
# 
#   custom_config = {
#     "enableEnhancedSecurityMonitoring" = "true"
#   }
# }

# ==========================================================
# Policy Permissions
# ==========================================================

locals {
  # Map static policy type labels to their apply-time IDs.
  # Keys are static strings (plan-time known) so they can safely be used in for_each.
  policy_id_by_type = {
    shared_interactive = length(databricks_cluster_policy.shared_interactive) > 0 ? databricks_cluster_policy.shared_interactive[0].id : null
    job_clusters       = length(databricks_cluster_policy.job_clusters) > 0 ? databricks_cluster_policy.job_clusters[0].id : null
    ml_clusters        = length(databricks_cluster_policy.ml_clusters) > 0 ? databricks_cluster_policy.ml_clusters[0].id : null
    lakeflow_pipelines = length(databricks_cluster_policy.lakeflow_pipelines) > 0 ? databricks_cluster_policy.lakeflow_pipelines[0].id : null
  }

  # Build permission assignments — key is static (policy_type + perm_key), value may contain apply-time IDs.
  policy_permission_grants = var.enable_cluster_policies ? {
    for pair in flatten([
      for policy_type, policy_id in local.policy_id_by_type : [
        for perm_key, perm_config in var.policy_permissions : {
          key                    = "${policy_type}_${perm_key}"
          policy_id              = policy_id
          group_name             = perm_config.group_name
          user_name              = perm_config.user_name
          service_principal_name = perm_config.service_principal
          permission_level       = perm_config.permission_level
        }
      ]
    ]) : pair.key => pair
  } : {}
}

resource "databricks_permissions" "cluster_policies" {
  for_each = local.policy_permission_grants

  cluster_policy_id = each.value.policy_id

  dynamic "access_control" {
    for_each = each.value.group_name != null ? [1] : []
    content {
      group_name       = each.value.group_name
      permission_level = each.value.permission_level
    }
  }

  dynamic "access_control" {
    for_each = each.value.user_name != null ? [1] : []
    content {
      user_name        = each.value.user_name
      permission_level = each.value.permission_level
    }
  }

  dynamic "access_control" {
    for_each = each.value.service_principal_name != null ? [1] : []
    content {
      service_principal_name = each.value.service_principal_name
      permission_level       = each.value.permission_level
    }
  }
}

# ==========================================================
# Workspace Security Settings
# ==========================================================

resource "databricks_workspace_conf" "security_settings" {
  custom_config = {
    # ML experiment tracking — removed: enableDatabricksAutologging not supported in current workspace version
    # "enableDatabricksAutologging" = tostring(var.enable_ml_autologging)

    # Unity Catalog user isolation — each user runs in their own container
    "enforceUserIsolation" = tostring(var.enforce_user_isolation)
  }
}

# Note: Audit log delivery (enableAuditLog, system tables) requires
# an external storage destination and is scoped to Epic 4 (monitoring module).
