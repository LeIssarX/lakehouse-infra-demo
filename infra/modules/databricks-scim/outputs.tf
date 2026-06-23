# ==========================================================
# Outputs
# ==========================================================

output "application_id" {
  description = "Application (client) ID of the SCIM app"
  value       = azuread_application.scim.client_id
}

output "application_object_id" {
  description = "Object ID of the SCIM app registration"
  value       = azuread_application.scim.object_id
}

output "service_principal_id" {
  description = "Object ID of the SCIM service principal"
  value       = azuread_service_principal.scim.object_id
}

output "scim_tenant_url" {
  description = "SCIM tenant URL for Databricks (use in Azure AD Enterprise App provisioning)"
  value       = local.scim_tenant_url
}

output "manual_steps_required" {
  description = "Manual steps still required to complete SCIM setup"
  value = {
    step_1              = "Generate SCIM token via Databricks Account Console (Settings → User provisioning)"
    step_2              = "Configure Enterprise Application provisioning in Azure Portal"
    step_3              = "Set Tenant URL: ${local.scim_tenant_url}"
    step_4              = "Set Secret Token: <token from step 1>"
    step_5              = "Test connection and start provisioning"
    account_console_url = "https://accounts.azuredatabricks.net"
  }
}

output "assigned_groups" {
  description = "Azure AD groups assigned to SCIM app"
  value       = { for k, v in var.assigned_groups : k => v.display_name }
}

output "assigned_users" {
  description = "Azure AD users assigned to SCIM app"
  value       = { for k, v in var.assigned_users : k => v.display_name }
}
