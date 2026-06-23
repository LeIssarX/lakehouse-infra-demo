# ==========================================================
# Databricks Account Identity Management (AIM) Module
# ==========================================================
# Modern identity sync from Azure AD to Databricks
# Replaces legacy SCIM with simpler, native Azure integration

# ==========================================================
# Data Sources
# ==========================================================

data "azuread_client_config" "current" {}

# ==========================================================
# Azure AD Security Groups
# ==========================================================
# Option 1: Create Azure AD groups (requires Group.ReadWrite.All permission)

resource "azuread_group" "databricks_groups" {
  for_each = var.create_azure_groups ? var.groups : {}

  display_name     = each.value.display_name
  description      = each.value.description
  security_enabled = true
  mail_enabled     = false
  mail_nickname    = each.value.mail_nickname

  lifecycle {
    prevent_destroy = false # Set to true in production
  }
}

# Option 2: Use existing Azure AD groups (when create_azure_groups = false and no pre-created IDs)
# Skipped entirely when aim_group_ids is provided — no Azure AD lookup needed.

data "azuread_group" "existing_groups" {
  for_each = (var.create_azure_groups || length(var.aim_group_ids) > 0) ? {} : var.groups

  display_name     = each.value.display_name
  security_enabled = true
}

# Unified local for group object IDs.
# Priority: aim_group_ids (pre-created, no permissions needed) > created > looked-up.
locals {
  group_object_ids = length(var.aim_group_ids) > 0 ? var.aim_group_ids : {
    for key, _ in var.groups :
    key => var.create_azure_groups ? azuread_group.databricks_groups[key].object_id : data.azuread_group.existing_groups[key].object_id
  }
}

# ==========================================================
# Databricks Account Groups (via AIM)
# ==========================================================
# Sync Azure AD groups to Databricks Account level
# This uses native Azure AD federation, no SCIM required

resource "databricks_group" "account_groups" {
  for_each = var.groups
  provider = databricks.account

  display_name               = each.value.display_name
  external_id                = local.group_object_ids[each.key]
  force                      = true # adopt existing groups instead of failing on greenfield re-runs
  allow_cluster_create       = each.value.allow_cluster_create
  allow_instance_pool_create = each.value.allow_instance_pool_create

  depends_on = [
    azuread_group.databricks_groups,
    data.azuread_group.existing_groups
  ]
}

# ==========================================================
# Workspace Access Assignments
# ==========================================================
# Grant groups access to specific workspaces

resource "databricks_mws_permission_assignment" "workspace_access" {
  for_each = var.workspace_assignments
  provider = databricks.account

  workspace_id = each.value.workspace_id
  principal_id = databricks_group.account_groups[each.value.group_key].id
  permissions  = each.value.permissions
}

# ==========================================================
# User Assignments (Optional)
# ==========================================================
# For direct user assignments outside of groups

resource "databricks_user" "account_users" {
  for_each = var.direct_users
  provider = databricks.account

  user_name    = each.value.user_principal_name
  display_name = each.value.display_name
  external_id  = each.value.object_id
  force        = false
  active       = true

  lifecycle {
    # Prevent drift from manual changes
    ignore_changes = [
      active,
      display_name
    ]
  }
}

# ==========================================================
# Workspace-Level Group Assignments
# ==========================================================
# Assign workspace-level permissions to account groups

resource "databricks_group_member" "workspace_group_members" {
  for_each = { for assignment in local.workspace_group_assignments : "${assignment.workspace_id}_${assignment.group_key}_${assignment.workspace_group}" => assignment }
  provider = databricks.workspace

  group_id  = each.value.workspace_group_id
  member_id = databricks_group.account_groups[each.value.group_key].id

  lifecycle {
    create_before_destroy = true
  }
}

# ==========================================================
# Local Values
# ==========================================================

locals {
  # Flatten workspace group assignments for easier iteration
  workspace_group_assignments = flatten([
    for ws_key, ws in var.workspace_group_assignments : [
      for group_key, group_config in ws.groups : {
        workspace_id       = ws.workspace_id
        group_key          = group_key
        workspace_group    = group_config.workspace_group
        workspace_group_id = group_config.workspace_group_id
      }
    ]
  ])
}
