# ==========================================================
# Module: Databricks Compute — Interactive Clusters
# ==========================================================
# Provisions one interactive cluster per entry in var.clusters.
# Clusters are addressed by their map key: module.cluster["engineering"]
#
# To add a cluster: add an entry to clusters = { ... } in your *.tfvars
# To remove a cluster: remove the entry and run tofu apply
#
# Prod best practice: clusters = {} (use Job Clusters via DABs instead)

module "cluster" {
  for_each = var.clusters

  source = "./modules/databricks-compute"

  providers = {
    databricks = databricks.workspace
  }

  name                     = each.key
  environment              = var.environment
  owner                    = each.value.owner
  node_type                = each.value.node_type
  min_workers              = each.value.min_workers
  max_workers              = each.value.max_workers
  spark_version            = each.value.spark_version
  runtime_engine           = each.value.runtime_engine
  data_security_mode       = each.value.data_security_mode
  enable_spot_instances    = each.value.enable_spot
  auto_termination_minutes = each.value.auto_termination_minutes
  cluster_policy_id        = try(module.governance.cluster_policy_ids[each.value.policy_key], null)
  tags                     = var.tags

  depends_on = [module.governance, module.unity_catalog]
}
