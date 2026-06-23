# ==========================================================
# Storage Module - ADLS Gen2 for Unity Catalog
# ==========================================================

# Generate a random suffix for globally unique storage account name (create mode only)
resource "random_string" "storage_suffix" {
  count   = var.account_mode == "create" ? 1 : 0
  length  = 6
  special = false
  upper   = false
  numeric = true
}

locals {
  # Storage account name: prefix + random suffix (must be globally unique, max 24 chars)
  storage_account_name = var.account_mode == "create" ? "${var.storage_account_prefix}${random_string.storage_suffix[0].result}" : var.existing_account_name

  # Determine account kind based on tier
  actual_account_kind = var.account_tier == "Premium" ? "BlockBlobStorage" : var.account_kind

  # Determine valid replication types for tier
  actual_replication_type = var.account_tier == "Premium" && contains(["GRS", "GZRS", "RAGRS", "RAGZRS"], var.replication_type) ? "LRS" : var.replication_type
}

# ==========================================================
# Storage Account (ADLS Gen2) — create new, or attach to an existing account
# ==========================================================
# count makes these addresses indexed ([0]). OpenTofu auto-detects the move
# (verified against live dev: 0 destroy). Optional safety-net script + details:
# docs/migration/per-resource-create-existing-modes.md

resource "azurerm_storage_account" "main" {
  count                    = var.account_mode == "create" ? 1 : 0
  name                     = local.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = var.account_tier
  account_kind             = local.actual_account_kind
  account_replication_type = local.actual_replication_type

  # CRITICAL: Enable hierarchical namespace for ADLS Gen2 (required for Unity Catalog)
  is_hns_enabled = true

  # Security settings
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true # Required for some Unity Catalog operations
  min_tls_version                 = "TLS1_2"

  # Disable public access when private endpoint is configured
  public_network_access_enabled = var.enable_private_endpoint ? false : true

  # Enable blob properties
  blob_properties {
    # Soft delete for blobs
    dynamic "delete_retention_policy" {
      for_each = var.enable_soft_delete ? [1] : []
      content {
        days = var.soft_delete_retention_days
      }
    }

    # Container soft delete
    dynamic "container_delete_retention_policy" {
      for_each = var.enable_soft_delete ? [1] : []
      content {
        days = var.soft_delete_retention_days
      }
    }

    # Versioning (for data protection)
    versioning_enabled = var.enable_versioning
  }

  tags = merge(
    var.tags,
    {
      "ManagedBy"   = "OpenTofu"
      "Module"      = "storage"
      "Environment" = var.environment
    }
  )
}

# Reuse an existing ADLS Gen2 account (existing mode)
data "azurerm_storage_account" "existing" {
  count               = var.account_mode == "existing" ? 1 : 0
  name                = var.existing_account_name
  resource_group_name = var.resource_group_name
}

locals {
  # Single source of truth for the account, regardless of create/existing.
  account_id           = var.account_mode == "existing" ? data.azurerm_storage_account.existing[0].id : azurerm_storage_account.main[0].id
  account_name         = var.account_mode == "existing" ? data.azurerm_storage_account.existing[0].name : azurerm_storage_account.main[0].name
  account_dfs_endpoint = var.account_mode == "existing" ? data.azurerm_storage_account.existing[0].primary_dfs_endpoint : azurerm_storage_account.main[0].primary_dfs_endpoint
  account_dfs_host     = var.account_mode == "existing" ? data.azurerm_storage_account.existing[0].primary_dfs_host : azurerm_storage_account.main[0].primary_dfs_host
}

# ==========================================================
# Containers (Data Layers)
# ==========================================================
# Created only in 'create' mode. An existing account is assumed to already hold
# its containers (the 7-layer medallion layout), so they are left unmanaged.

resource "azurerm_storage_container" "containers" {
  for_each = var.account_mode == "create" ? toset(var.containers) : toset([])

  name                  = each.value
  storage_account_id    = local.account_id
  container_access_type = "private"
}

# ==========================================================
# RBAC - Databricks Access Connector
# ==========================================================

# Grant Storage Blob Data Contributor to Databricks Access Connector
# This allows Unity Catalog to read/write data via managed identity
resource "azurerm_role_assignment" "databricks_storage_contributor" {
  scope                = local.account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.databricks_access_connector_id
}

# ==========================================================
# Lifecycle Management Policy (Optional)
# ==========================================================

resource "azurerm_storage_management_policy" "lifecycle" {
  count = var.enable_lifecycle_policy ? 1 : 0

  storage_account_id = local.account_id

  dynamic "rule" {
    for_each = var.lifecycle_containers
    content {
      name    = "${rule.value}-lifecycle"
      enabled = true

      filters {
        prefix_match = ["${rule.value}/"]
        blob_types   = ["blockBlob"]
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than    = var.cool_after_days
          tier_to_archive_after_days_since_modification_greater_than = var.archive_after_days

          # Deletion is optional — set delete_after_days = 0 to disable
          delete_after_days_since_modification_greater_than = var.delete_after_days > 0 ? var.delete_after_days : null
        }
      }
    }
  }
}

# ==========================================================
# Private Endpoint (Optional)
# ==========================================================
# Requires: enable_vnet_injection = true and private_endpoint_subnet_id set.
# See docs/migration/vnet-injection.md for VNet setup.

resource "azurerm_private_dns_zone" "storage_dfs" {
  count = var.enable_private_endpoint && var.create_private_dns_zone ? 1 : 0

  name                = "privatelink.dfs.core.windows.net"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_dfs" {
  count = var.enable_private_endpoint && var.create_private_dns_zone ? 1 : 0

  name                  = "${local.account_name}-dfs-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.storage_dfs[0].name
  virtual_network_id    = var.private_dns_zone_vnet_id
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "storage_dfs" {
  count = var.enable_private_endpoint ? 1 : 0

  name                = "${local.account_name}-dfs-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${local.account_name}-dfs-psc"
    private_connection_resource_id = local.account_id
    is_manual_connection           = false
    subresource_names              = ["dfs"]
  }

  dynamic "private_dns_zone_group" {
    for_each = var.create_private_dns_zone ? [1] : []
    content {
      name                 = "dfs-dns-zone-group"
      private_dns_zone_ids = [azurerm_private_dns_zone.storage_dfs[0].id]
    }
  }

  tags = var.tags
}
