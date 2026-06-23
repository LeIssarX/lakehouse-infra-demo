# ==========================================================
# Databricks SCIM Integration Module
# ==========================================================
# Automates SCIM provisioning setup for Databricks
# Note: Some steps still require manual configuration in Azure Portal

# ==========================================================
# Data Sources
# ==========================================================

data "azuread_client_config" "current" {}

# ==========================================================
# Azure AD Application for SCIM
# ==========================================================

resource "azuread_application" "scim" {
  display_name = var.application_name
  owners       = [data.azuread_client_config.current.object_id]

  # Required for SCIM provisioning
  sign_in_audience = "AzureADMyOrg"

  # API permissions for provisioning
  required_resource_access {
    # Microsoft Graph
    resource_app_id = "00000003-0000-0000-c000-000000000000"

    resource_access {
      # User.Read.All
      id   = "df021288-bdef-4463-88db-98f22de89214"
      type = "Role"
    }

    resource_access {
      # GroupMember.Read.All
      id   = "98830695-27a2-44f7-8c18-0c3ebc9698f6"
      type = "Role"
    }
  }

  tags = var.tags
}

# ==========================================================
# Service Principal
# ==========================================================

resource "azuread_service_principal" "scim" {
  client_id                    = azuread_application.scim.client_id
  app_role_assignment_required = true
  owners                       = [data.azuread_client_config.current.object_id]

  tags = var.tags
}

# ==========================================================
# Assign Azure AD Groups to SCIM App
# ==========================================================

resource "azuread_app_role_assignment" "groups" {
  for_each = var.assigned_groups

  app_role_id         = "00000000-0000-0000-0000-000000000000" # Default access role
  principal_object_id = each.value.object_id
  resource_object_id  = azuread_service_principal.scim.object_id
}

# ==========================================================
# Assign Azure AD Users to SCIM App
# ==========================================================

resource "azuread_app_role_assignment" "users" {
  for_each = var.assigned_users

  app_role_id         = "00000000-0000-0000-0000-000000000000" # Default access role
  principal_object_id = each.value.object_id
  resource_object_id  = azuread_service_principal.scim.object_id
}

# ==========================================================
# Databricks SCIM Token (Account-Level)
# ==========================================================
# Note: This requires account-level provider authentication
# The token will be used for Azure AD SCIM provisioning

# IMPORTANT: The SCIM token must be created via Databricks Account Console UI
# This is a placeholder for documentation purposes
# See: https://accounts.azuredatabricks.net/ → Settings → User provisioning

# Manual step required:
# 1. Log into Account Console
# 2. Go to Settings → User provisioning
# 3. Click "Generate token"
# 4. Copy token and store in Key Vault or GitHub Secret

# ==========================================================
# Outputs for Manual Configuration
# ==========================================================

locals {
  scim_tenant_url = "https://accounts.azuredatabricks.net/api/2.0/accounts/${var.databricks_account_id}/scim/v2"
}
