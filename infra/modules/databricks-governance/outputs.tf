output "cluster_policy_ids" {
  description = "Map of cluster policy names to their IDs"
  value = var.enable_cluster_policies ? {
    shared_interactive = try(databricks_cluster_policy.shared_interactive[0].id, null)
    job_clusters       = try(databricks_cluster_policy.job_clusters[0].id, null)
    ml_clusters        = try(databricks_cluster_policy.ml_clusters[0].id, null)
    lakeflow_pipelines = try(databricks_cluster_policy.lakeflow_pipelines[0].id, null)
  } : {}
}

output "shared_interactive_policy_id" {
  description = "ID of the shared interactive cluster policy (for use in databricks-compute module)"
  value       = var.enable_cluster_policies ? try(databricks_cluster_policy.shared_interactive[0].id, null) : null
}

output "policy_names" {
  description = "List of created cluster policy names"
  value = var.enable_cluster_policies ? [
    try(databricks_cluster_policy.shared_interactive[0].name, ""),
    try(databricks_cluster_policy.job_clusters[0].name, ""),
    try(databricks_cluster_policy.ml_clusters[0].name, ""),
    try(databricks_cluster_policy.lakeflow_pipelines[0].name, "")
  ] : []
}

output "token_policy_enabled" {
  description = "Whether token management policy is enabled"
  value       = var.enable_token_policy
}

output "ip_access_lists_enabled" {
  description = "Whether IP access lists are enabled"
  value       = var.enable_ip_access_lists
}

output "automatic_updates_enabled" {
  description = "Whether automatic cluster updates are enabled"
  value       = var.enable_automatic_cluster_updates
}
