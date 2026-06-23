output "cluster_id" {
  description = "ID of the interactive cluster"
  value       = databricks_cluster.this.id
}

output "cluster_url" {
  description = "URL to the interactive cluster in the Databricks UI"
  value       = databricks_cluster.this.url
}
