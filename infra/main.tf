# Lakehouse Blueprint — Root Module
# Usage: see infra/CLAUDE.md (or ./scripts/tofu-wrapper.sh).

# ==========================================================
# Data Sources
# ==========================================================

data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# ==========================================================
# Remote State: Dev Environment (for shared metastore)
# ==========================================================
# Required when unity_catalog_metastore_mode = "existing" (prod only).
# Reads dev's state to retrieve the shared regional metastore ID.
#
# Activation: set dev_remote_state_resource_group in prod.tfvars.
# Dev leaves this variable null → remote state is not read.

data "terraform_remote_state" "dev" {
  count   = var.dev_remote_state_resource_group != null ? 1 : 0
  backend = "azurerm"

  config = {
    resource_group_name  = var.dev_remote_state_resource_group
    storage_account_name = var.dev_remote_state_storage_account
    container_name       = var.dev_remote_state_container
    key                  = var.dev_remote_state_key
    use_oidc             = true
  }
}

locals {
  # Metastore ID sourced from dev remote state (null for dev, populated for prod)
  dev_metastore_id = length(data.terraform_remote_state.dev) > 0 ? data.terraform_remote_state.dev[0].outputs.unity_catalog_metastore_id : null
}
