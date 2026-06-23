# ==========================================================
# Module: Network
# ==========================================================
# Only create VNet resources when VNet injection is enabled

module "network" {
  source = "./modules/network"
  count  = var.enable_vnet_injection ? 1 : 0

  resource_group_name = local.resource_group_name
  location            = local.resource_group_location

  vnet_mode                         = var.vnet_mode
  existing_vnet_name                = var.existing_vnet_name
  existing_vnet_resource_group_name = var.existing_vnet_resource_group_name

  vnet_name                       = var.vnet_name
  vnet_address_space              = var.vnet_address_space
  public_subnet_address_prefixes  = var.public_subnet_address_prefixes
  private_subnet_address_prefixes = var.private_subnet_address_prefixes
  databricks_workspace_name       = var.databricks_workspace_name

  tags = var.tags
}
