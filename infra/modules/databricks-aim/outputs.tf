# ==========================================================
# Outputs - Databricks AIM Module
# ==========================================================

output "azure_ad_groups" {
  description = "Created Azure AD groups for Databricks access"
  value = {
    for k, group in azuread_group.databricks_groups : k => {
      object_id    = group.object_id
      display_name = group.display_name
      description  = group.description
    }
  }
}

output "databricks_account_groups" {
  description = "Databricks account-level groups synced from Azure AD"
  value = {
    for k, group in databricks_group.account_groups : k => {
      id           = group.id
      display_name = group.display_name
      external_id  = group.external_id
    }
  }
}

output "workspace_assignments" {
  description = "Group assignments to workspaces"
  value = {
    for k, assignment in databricks_mws_permission_assignment.workspace_access : k => {
      workspace_id = assignment.workspace_id
      principal_id = assignment.principal_id
      permissions  = assignment.permissions
    }
  }
}

output "databricks_account_users" {
  description = "Directly assigned Databricks users"
  value = {
    for k, user in databricks_user.account_users : k => {
      id        = user.id
      user_name = user.user_name
    }
  }
  sensitive = false
}

output "setup_summary" {
  description = "Summary of AIM configuration"
  value = {
    groups_created        = length(azuread_group.databricks_groups)
    workspace_assignments = length(databricks_mws_permission_assignment.workspace_access)
    direct_users          = length(databricks_user.account_users)
    ready                 = true
  }
}

output "next_steps" {
  description = "Post-deployment instructions"
  value       = <<-EOT
    ✅ Azure AD Identity Management (AIM) Setup Complete!
    
    Azure AD Groups Created: ${length(azuread_group.databricks_groups)}
    Workspace Assignments: ${length(databricks_mws_permission_assignment.workspace_access)}
    
    What's Next:
    
    1. Add Users to Azure AD Groups
       - Go to Azure Portal → Azure Active Directory → Groups
       - Select the created groups and add users
       - Users will automatically sync to Databricks (within minutes)
    
    2. Verify Sync in Databricks
       - Login to Databricks Account Console: https://accounts.azuredatabricks.net
       - Navigate to User Management → Groups
       - Verify groups and users appear
    
    3. Assign Workspace Permissions (if needed)
       - Groups are already assigned to workspaces via Terraform
       - Additional permissions can be granted via Databricks UI
    
    No manual configuration required! ✨
    AIM handles identity federation automatically.
  EOT
}
