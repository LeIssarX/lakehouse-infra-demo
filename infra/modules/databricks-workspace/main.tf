# ==========================================================
# Databricks Workspace Module
# ==========================================================

locals {
  # Auto-generate managed resource group name if not provided
  managed_rg_name = var.managed_resource_group_name != null ? var.managed_resource_group_name : "databricks-rg-${var.workspace_name}"
}

# ==========================================================
# Databricks Access Connector (Managed Identity for Unity Catalog)
# ==========================================================

resource "azurerm_databricks_access_connector" "main" {
  name                = "${var.workspace_name}-access-connector"
  resource_group_name = var.resource_group_name
  location            = var.location

  identity {
    type = "SystemAssigned"
  }

  tags = merge(
    var.tags,
    {
      "ManagedBy"   = "OpenTofu"
      "Module"      = "databricks-workspace"
      "Environment" = var.environment
    }
  )
}

# ==========================================================
# Databricks Workspace — create new, or attach to an existing one
# ==========================================================
# count makes the address indexed ([0]); OpenTofu auto-detects the move
# (verified against live dev: 0 destroy). The access connector is unchanged.
# Details: docs/migration/per-resource-create-existing-modes.md

resource "azurerm_databricks_workspace" "main" {
  count               = var.workspace_mode == "create" ? 1 : 0
  name                = var.workspace_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku

  managed_resource_group_name = local.managed_rg_name

  # Public network access (set to false for Private Link only)
  public_network_access_enabled = var.public_network_access_enabled

  # Network configuration (VNet injection)
  dynamic "custom_parameters" {
    for_each = var.enable_vnet_injection ? [1] : []
    content {
      no_public_ip        = true # Recommended for production
      public_subnet_name  = var.public_subnet_name
      private_subnet_name = var.private_subnet_name
      virtual_network_id  = var.virtual_network_id

      public_subnet_network_security_group_association_id  = var.public_nsg_association_id
      private_subnet_network_security_group_association_id = var.private_nsg_association_id
    }
  }

  # Enhanced Security & Compliance
  # (Available with Premium tier only)
  dynamic "enhanced_security_compliance" {
    for_each = var.sku == "premium" && var.enable_enhanced_security ? [1] : []
    content {
      # Automatic cluster updates (monthly maintenance window)
      automatic_cluster_update_enabled = var.enable_automatic_cluster_updates

      # Enhanced security monitoring
      enhanced_security_monitoring_enabled = true

      # Compliance security profile (HIPAA, PCI-DSS)
      compliance_security_profile_enabled   = var.enable_compliance_profile
      compliance_security_profile_standards = var.compliance_standards
    }
  }

  tags = merge(
    var.tags,
    {
      "ManagedBy"   = "OpenTofu"
      "Module"      = "databricks-workspace"
      "Environment" = var.environment
    }
  )
}

# Reuse an existing workspace (existing mode)
data "azurerm_databricks_workspace" "existing" {
  count               = var.workspace_mode == "existing" ? 1 : 0
  name                = var.workspace_name
  resource_group_name = var.resource_group_name
}

locals {
  # Single source of truth for the workspace, regardless of create/existing.
  ws_id           = var.workspace_mode == "existing" ? data.azurerm_databricks_workspace.existing[0].id : azurerm_databricks_workspace.main[0].id
  ws_workspace_id = var.workspace_mode == "existing" ? data.azurerm_databricks_workspace.existing[0].workspace_id : azurerm_databricks_workspace.main[0].workspace_id
  ws_url          = var.workspace_mode == "existing" ? data.azurerm_databricks_workspace.existing[0].workspace_url : azurerm_databricks_workspace.main[0].workspace_url
  ws_name         = var.workspace_mode == "existing" ? data.azurerm_databricks_workspace.existing[0].name : azurerm_databricks_workspace.main[0].name
  ws_sku          = var.workspace_mode == "existing" ? data.azurerm_databricks_workspace.existing[0].sku : azurerm_databricks_workspace.main[0].sku
  # The workspace data source does not export managed_resource_group_id; null in existing mode.
  ws_managed_rg_id = var.workspace_mode == "existing" ? null : azurerm_databricks_workspace.main[0].managed_resource_group_id
}

# ==========================================================
# Workspace-Level Settings
# ==========================================================
# Token policies, IP access lists, cluster policies, and workspace
# configuration settings are managed by the databricks-governance module.

# ==========================================================
# Notes on Unity Catalog Setup
# ==========================================================

# Unity Catalog requires account-level configuration:
# 1. Create metastore at Databricks account level
# 2. Create storage credential (using access connector)
# 3. Assign metastore to this workspace
# 4. Configure external locations and catalogs

# This is handled by the unity-catalog module
