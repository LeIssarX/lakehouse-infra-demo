# ==========================================================
# Module: Databricks Governance
# ==========================================================

module "governance" {
  source = "./modules/databricks-governance"

  providers = {
    databricks = databricks.workspace
  }

  workspace_url = module.databricks_workspace.workspace_url
  environment   = var.environment

  # Cluster policies
  enable_cluster_policies = var.enable_cluster_policies
  require_unity_catalog   = var.require_unity_catalog
  require_serverless      = var.require_serverless

  # Cost controls
  auto_termination_minutes          = var.auto_termination_minutes
  max_cluster_lifetime_minutes      = var.max_cluster_lifetime_minutes
  max_workers_limit                 = var.max_workers_limit
  enable_spot_instances             = var.enable_spot_instances

  # Allowed node types
  allowed_node_types = var.allowed_node_types

  # Token policy
  enable_token_policy     = var.enable_token_policy
  max_token_lifetime_days = var.max_token_lifetime_days

  # IP access lists (optional)
  enable_ip_access_lists = var.enable_ip_access_lists
  allowed_ip_ranges      = var.governance_allowed_ips

  # Policy permissions — managed via AIM workspace assignments
  policy_permissions = {}

  # Automatic updates
  enable_automatic_cluster_updates = var.enable_automatic_cluster_updates

  # Workspace security settings
  enable_ml_autologging  = var.enable_ml_autologging
  enforce_user_isolation = var.enforce_user_isolation

  # Policy tuning
  interactive_max_clusters_per_user = var.interactive_max_clusters_per_user
  job_max_clusters_per_user         = var.job_max_clusters_per_user
  ml_max_clusters_per_user          = var.ml_max_clusters_per_user
  autotermination_min_floor         = var.autotermination_min_floor
  job_autotermination_minutes       = var.job_autotermination_minutes
  ml_autotermination_min            = var.ml_autotermination_min
  ml_autotermination_max            = var.ml_autotermination_max
  ml_autotermination_default        = var.ml_autotermination_default
  ml_spark_version                  = var.ml_spark_version
  ml_allowed_node_types             = var.ml_allowed_node_types
  pipeline_max_workers              = var.pipeline_max_workers
  tags = var.tags

  depends_on = [module.databricks_workspace, module.unity_catalog]
}
