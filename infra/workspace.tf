# ==========================================================
# Module: Databricks Workspace
# ==========================================================

module "databricks_workspace" {
  source = "./modules/databricks-workspace"

  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  environment         = var.environment

  workspace_mode            = var.databricks_workspace_mode
  workspace_name            = var.databricks_workspace_name
  sku                       = var.workspace_sku
  enable_unity_catalog      = var.enable_unity_catalog
  enable_serverless_compute = var.enable_serverless_compute

  # VNet injection
  enable_vnet_injection      = var.enable_vnet_injection
  public_subnet_name         = var.enable_vnet_injection ? module.network[0].public_subnet_name : null
  private_subnet_name        = var.enable_vnet_injection ? module.network[0].private_subnet_name : null
  virtual_network_id         = var.enable_vnet_injection ? module.network[0].vnet_id : null
  public_nsg_association_id  = var.enable_vnet_injection ? module.network[0].public_nsg_association_id : null
  private_nsg_association_id = var.enable_vnet_injection ? module.network[0].private_nsg_association_id : null

  # Security
  enable_enhanced_security         = var.enable_enhanced_security
  enable_automatic_cluster_updates = var.enable_automatic_cluster_updates
  public_network_access_enabled    = var.enable_public_access

  tags = var.tags
}
