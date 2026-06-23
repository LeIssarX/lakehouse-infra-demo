# ==========================================================
# Providers
# ==========================================================

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    key_vault {
      purge_soft_delete_on_destroy    = false # Keep soft-deleted vaults
      recover_soft_deleted_key_vaults = true
    }
  }

  # Authentication: Use `az login` for local development.
  # For CI/CD, set ARM_CLIENT_ID / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID env vars
  # and use OIDC (see docs/guides/cicd-setup.md).
}

provider "azuread" {
  # Uses same authentication as azurerm provider
}

# Databricks Account Provider (for AIM and account-level resources)
provider "databricks" {
  alias = "account"

  host       = "https://accounts.azuredatabricks.net"
  account_id = var.databricks_account_id
}

# Databricks Workspace Provider
#
# Two auth modes (mutually exclusive — provider rejects both simultaneously):
#
#   CI/CD (default): azure_workspace_resource_id → Azure AD via ARM_CLIENT_ID etc.
#     Leave databricks_workspace_url = null (the default).
#
#   Local dev: set databricks_workspace_url in dev.tfvars to your workspace URL.
#     This nulls out azure_workspace_resource_id so PAT auth via
#     DATABRICKS_CONFIG_PROFILE=aschwabe-dev works without conflict.
#     Get your workspace URL from: tofu output workspace_url
#
provider "databricks" {
  alias = "workspace"

  # Active in CI/CD (when databricks_workspace_url is null)
  azure_workspace_resource_id = var.databricks_workspace_url == null ? "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Databricks/workspaces/${var.databricks_workspace_name}" : null

  # Active in local dev (when databricks_workspace_url is set in tfvars)
  host = var.databricks_workspace_url
}
