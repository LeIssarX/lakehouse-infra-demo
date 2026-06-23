# ==========================================================
# Resource Group  (create new, or attach to an existing one)
# ==========================================================
# resource_group_mode = "create"   → manage a new RG named var.resource_group_name
# resource_group_mode = "existing" → reuse an existing RG (data source)
#
# NOTE: count makes the address indexed (.main[0]). OpenTofu auto-detects this as
# a move (verified against live dev: plan shows 0 destroy). Optional safety-net
# script + details: docs/migration/per-resource-create-existing-modes.md

resource "azurerm_resource_group" "main" {
  count    = var.resource_group_mode == "create" ? 1 : 0
  name     = var.resource_group_name
  location = var.location

  tags = merge(
    var.tags,
    {
      "Environment" = var.environment
      "ManagedBy"   = "OpenTofu"
      "Project"     = var.project_name
    }
  )
}

data "azurerm_resource_group" "existing" {
  count = var.resource_group_mode == "existing" ? 1 : 0
  name  = coalesce(var.existing_resource_group_name, var.resource_group_name)
}

locals {
  # Single source of truth for the resource group, regardless of create/existing.
  resource_group_name = (
    var.resource_group_mode == "existing"
    ? data.azurerm_resource_group.existing[0].name
    : azurerm_resource_group.main[0].name
  )
  resource_group_location = (
    var.resource_group_mode == "existing"
    ? data.azurerm_resource_group.existing[0].location
    : azurerm_resource_group.main[0].location
  )
  resource_group_id = (
    var.resource_group_mode == "existing"
    ? data.azurerm_resource_group.existing[0].id
    : azurerm_resource_group.main[0].id
  )
}

# ==========================================================
# Log Analytics Workspace
# ==========================================================
# Centralized logging and monitoring for compliance and security audit

resource "azurerm_log_analytics_workspace" "main" {
  # Namespaced by project slug so multiple instances coexist in one subscription.
  name                = "log-${var.project_slug}-${var.environment}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_days

  tags = var.tags
}
