# ==========================================================
# Databricks Workload Service Principal - Outputs
# ==========================================================

output "service_principal_name" {
  description = "Display name of the service principal"
  value       = var.service_principal_name
}

output "application_id" {
  description = "Azure AD application (client) ID - use this in databricks.yml as service_principal_name"
  value       = azuread_service_principal.workload.client_id
}

output "client_secret" {
  description = "Client secret for authentication (sensitive) - store this in CI/CD secrets"
  value       = var.create_client_secret && length(azuread_application_password.workload) > 0 ? azuread_application_password.workload[0].value : null
  sensitive   = true
}

output "object_id" {
  description = "Azure AD service principal object ID"
  value       = azuread_service_principal.workload.object_id
}

output "databricks_sp_id" {
  description = "Databricks service principal ID (internal Databricks identifier)"
  value       = databricks_service_principal.workload.id
}

output "databricks_sp_application_id" {
  description = "Databricks service principal application ID (matches Azure AD client ID)"
  value       = databricks_service_principal.workload.application_id
}

output "key_vault_secret_names" {
  description = "Names of secrets stored in Key Vault (if enabled)"
  value = var.store_credentials_in_keyvault && var.key_vault_id != null ? {
    client_id     = "${var.secret_prefix}-client-id"
    client_secret = var.create_client_secret ? "${var.secret_prefix}-client-secret" : null
  } : null
}
