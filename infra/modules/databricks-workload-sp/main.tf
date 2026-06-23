# ==========================================================
# Databricks Workload Service Principal Module
# ==========================================================
# Creates and configures Azure AD service principals for running
# Databricks workloads (jobs, pipelines, workflows) in production.
#
# This module:
# 1. Creates an Azure AD application and service principal
# 2. Registers the SP in Databricks
# 3. Grants Unity Catalog permissions (least privilege)
# 4. Outputs credentials for workload configuration
#
# Use this for production workloads that need dedicated identity.
# Dev workloads typically run as user identity.
# ==========================================================

# ==========================================================
# Azure AD Application & Service Principal
# ==========================================================

resource "azuread_application" "workload" {
  display_name = var.service_principal_name
  owners       = var.owners

  # Optional: Add app roles or API permissions here
  # required_resource_access { ... }

  lifecycle {
    # Azure AD auto-adds the creator as owner at creation time, causing drift
    # against owners = []. Updating owners requires Application.ReadWrite.OwnedBy
    # which the CI/CD SP may not have. Owners are set correctly at creation.
    ignore_changes = [owners]
  }
}

resource "azuread_service_principal" "workload" {
  client_id                    = azuread_application.workload.client_id
  app_role_assignment_required = false
  owners                       = var.owners

  tags = concat(
    ["opentofu", "databricks", "workload"],
    var.tags
  )

  lifecycle {
    # Same owner drift issue as azuread_application above.
    # Tags updates also require Application.ReadWrite permissions.
    ignore_changes = [owners, tags]
  }
}

# Generate a client secret (rotate regularly via lifecycle)
resource "azuread_application_password" "workload" {
  count          = var.create_client_secret ? 1 : 0
  application_id = azuread_application.workload.id
  display_name   = "Workload secret (${var.environment})"

  # Use rotate_when_changed instead of deprecated end_date_relative
  rotate_when_changed = {
    rotation = var.client_secret_expiration
  }
}

# ==========================================================
# Databricks Service Principal
# ==========================================================

resource "databricks_service_principal" "workload" {
  provider = databricks.account

  application_id             = azuread_service_principal.workload.client_id
  display_name               = var.service_principal_name
  allow_cluster_create       = var.allow_cluster_create
  allow_instance_pool_create = var.allow_instance_pool_create

  # Workload SPs typically don't need admin rights
  workspace_access      = true
  databricks_sql_access = var.enable_sql_access

  lifecycle {
    ignore_changes = [active] # Don't fight Databricks if it disables the SP
  }
}

# Assign workspace-level permissions (optional)
resource "databricks_mws_permission_assignment" "workload_workspace" {
  count        = var.workspace_permission != null ? 1 : 0
  provider     = databricks.account
  workspace_id = var.databricks_workspace_id
  principal_id = databricks_service_principal.workload.id
  permissions  = [var.workspace_permission]
}

# ==========================================================
# Unity Catalog Grants
# ==========================================================

# Catalog-level grants
resource "databricks_grants" "catalog" {
  provider = databricks.workspace
  for_each = var.catalog_grants
  catalog  = each.key

  grant {
    principal  = databricks_service_principal.workload.application_id
    privileges = each.value
  }
}

# Schema-level grants
resource "databricks_grants" "schema" {
  provider = databricks.workspace
  for_each = var.schema_grants
  schema   = each.key

  grant {
    principal  = databricks_service_principal.workload.application_id
    privileges = each.value
  }
}

# Volume-level grants (optional)
resource "databricks_grants" "volume" {
  provider = databricks.workspace
  for_each = var.volume_grants
  volume   = each.key

  grant {
    principal  = databricks_service_principal.workload.application_id
    privileges = each.value
  }
}

# ==========================================================
# Optional: Store secret in Azure Key Vault
# ==========================================================

resource "azurerm_key_vault_secret" "workload_client_id" {
  count        = var.store_credentials_in_keyvault ? 1 : 0
  name         = "${var.secret_prefix}-client-id"
  value        = azuread_service_principal.workload.client_id
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "workload_client_secret" {
  count        = var.store_credentials_in_keyvault && var.create_client_secret ? 1 : 0
  name         = "${var.secret_prefix}-client-secret"
  value        = azuread_application_password.workload[0].value
  key_vault_id = var.key_vault_id

  lifecycle {
    ignore_changes = [value] # Allow manual rotation
  }
}

