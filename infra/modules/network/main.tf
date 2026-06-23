# ==========================================================
# Network Module - Azure VNet for Databricks
# ==========================================================
# vnet_mode = "create"   → provision VNet + subnets + NSG + route table
# vnet_mode = "existing" → reuse an existing VNet and its two Databricks subnets
#                          (assumed already delegated + NSG-associated)
#
# count makes every resource below indexed ([0]). OpenTofu auto-detects the move
# (verified against live dev: 0 destroy). Optional safety-net script + details:
# docs/migration/per-resource-create-existing-modes.md

locals {
  is_create = var.vnet_mode == "create"

  # Service delegation actions required by Databricks
  databricks_delegation_actions = [
    "Microsoft.Network/virtualNetworks/subnets/join/action",
    "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
    "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
  ]

  # Auto-generate names if not provided
  nsg_name         = var.nsg_name != null ? var.nsg_name : "${var.vnet_name}-nsg"
  route_table_name = var.route_table_name != null ? var.route_table_name : "${var.vnet_name}-rt"

  public_subnet_name  = "public-subnet-${var.databricks_workspace_name}"
  private_subnet_name = "private-subnet-${var.databricks_workspace_name}"
}

# ==========================================================
# Create-mode resources
# ==========================================================

resource "azurerm_virtual_network" "main" {
  count               = local.is_create ? 1 : 0
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space

  tags = merge(var.tags, { "ManagedBy" = "OpenTofu", "Module" = "network" })
}

resource "azurerm_network_security_group" "main" {
  count               = local.is_create ? 1 : 0
  name                = local.nsg_name
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, { "ManagedBy" = "OpenTofu", "Module" = "network" })
}

resource "azurerm_route_table" "main" {
  count               = local.is_create ? 1 : 0
  name                = local.route_table_name
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, { "ManagedBy" = "OpenTofu", "Module" = "network" })
}

resource "azurerm_subnet" "public" {
  count                = local.is_create ? 1 : 0
  name                 = local.public_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = var.public_subnet_address_prefixes

  delegation {
    name = "databricks-public-subnet-delegation"
    service_delegation {
      name    = "Microsoft.Databricks/workspaces"
      actions = local.databricks_delegation_actions
    }
  }
}

resource "azurerm_subnet" "private" {
  count                = local.is_create ? 1 : 0
  name                 = local.private_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = var.private_subnet_address_prefixes

  delegation {
    name = "databricks-private-subnet-delegation"
    service_delegation {
      name    = "Microsoft.Databricks/workspaces"
      actions = local.databricks_delegation_actions
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "public" {
  count                     = local.is_create ? 1 : 0
  subnet_id                 = azurerm_subnet.public[0].id
  network_security_group_id = azurerm_network_security_group.main[0].id
}

resource "azurerm_subnet_network_security_group_association" "private" {
  count                     = local.is_create ? 1 : 0
  subnet_id                 = azurerm_subnet.private[0].id
  network_security_group_id = azurerm_network_security_group.main[0].id
}

resource "azurerm_subnet_route_table_association" "public" {
  count          = local.is_create ? 1 : 0
  subnet_id      = azurerm_subnet.public[0].id
  route_table_id = azurerm_route_table.main[0].id
}

resource "azurerm_subnet_route_table_association" "private" {
  count          = local.is_create ? 1 : 0
  subnet_id      = azurerm_subnet.private[0].id
  route_table_id = azurerm_route_table.main[0].id
}

# ==========================================================
# Existing-mode data sources
# ==========================================================

data "azurerm_virtual_network" "existing" {
  count               = local.is_create ? 0 : 1
  name                = coalesce(var.existing_vnet_name, var.vnet_name)
  resource_group_name = coalesce(var.existing_vnet_resource_group_name, var.resource_group_name)
}

data "azurerm_subnet" "existing_public" {
  count                = local.is_create ? 0 : 1
  name                 = local.public_subnet_name
  virtual_network_name = data.azurerm_virtual_network.existing[0].name
  resource_group_name  = coalesce(var.existing_vnet_resource_group_name, var.resource_group_name)
}

data "azurerm_subnet" "existing_private" {
  count                = local.is_create ? 0 : 1
  name                 = local.private_subnet_name
  virtual_network_name = data.azurerm_virtual_network.existing[0].name
  resource_group_name  = coalesce(var.existing_vnet_resource_group_name, var.resource_group_name)
}
