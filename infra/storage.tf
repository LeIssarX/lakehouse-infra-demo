# ==========================================================
# Module: Storage (ADLS Gen2)
# ==========================================================
# Provisions one ADLS Gen2 storage account per entry in var.storage_accounts.
# The "lake" key is required and serves as the Unity Catalog Metastore root.
#
# To add a storage account: add an entry to storage_accounts = { ... } in your *.tfvars
# Unity Catalog External Locations are auto-registered for all containers of all accounts.

module "storage" {
  for_each = var.storage_accounts
  source   = "./modules/storage"

  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  environment         = var.environment

  # Create new vs reuse an existing account. Only the "lake" account honors
  # existing mode (it is the metastore root); any others always create.
  account_mode          = each.key == "lake" ? var.storage_account_mode : "create"
  existing_account_name = each.key == "lake" ? var.existing_storage_account_name : null

  storage_account_prefix     = var.storage_account_prefix
  containers                 = each.value.containers
  account_tier               = each.value.account_tier
  replication_type           = each.value.replication_type
  enable_lifecycle_policy    = each.value.enable_lifecycle_policy
  lifecycle_containers       = each.value.lifecycle_containers
  cool_after_days            = each.value.cool_after_days
  archive_after_days         = each.value.archive_after_days
  delete_after_days          = each.value.delete_after_days
  enable_soft_delete         = each.value.enable_soft_delete
  soft_delete_retention_days = each.value.soft_delete_retention_days

  # Unity Catalog RBAC
  databricks_access_connector_id = module.databricks_workspace.access_connector_principal_id

  # Private endpoint (opt-in, requires VNet injection)
  enable_private_endpoint    = var.enable_private_endpoint
  private_endpoint_subnet_id = var.enable_private_endpoint ? module.network[0].private_subnet_id : null
  create_private_dns_zone    = var.enable_private_endpoint
  private_dns_zone_vnet_id   = var.enable_private_endpoint ? module.network[0].vnet_id : null

  tags = var.tags

  depends_on = [module.databricks_workspace]
}
