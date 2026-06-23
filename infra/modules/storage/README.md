# Storage Module

This module creates a single Azure Data Lake Storage Gen2 (ADLS Gen2) account. It is called with `for_each` from `infra/storage.tf`, so multiple accounts can be provisioned from the `var.storage_accounts` map variable.

## Features

- **ADLS Gen2** with hierarchical namespace enabled (required for Unity Catalog)
- Configurable **containers** for lakehouse layers (landing/raw/curated/core/mart/reporting/sharing)
- **Private endpoint** support (requires VNet injection)
- **Lifecycle management** policies (automated Hot → Cool → Archive tiering)
- RBAC: Databricks Access Connector receives `Storage Blob Data Contributor` role

## for_each Pattern

This module is not called directly. It is invoked from `infra/storage.tf` using `for_each`:

```hcl
# infra/storage.tf
module "storage" {
  for_each = var.storage_accounts
  source   = "./modules/storage"

  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  environment                = var.environment
  storage_account_prefix     = "${var.storage_account_prefix}${each.key}"
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
  databricks_access_connector_id = module.databricks_workspace.access_connector_principal_id
  enable_private_endpoint    = var.enable_private_endpoint
  ...
  tags = var.tags
}
```

Operators configure storage accounts via the `storage_accounts` variable in their tfvars files:

```hcl
# infra/envs/dev/dev.tfvars
storage_account_prefix = "stlkhs"   # max 11 chars

storage_accounts = {
  # "lake" key is required — serves as Unity Catalog Metastore root
  "lake" = {
    containers       = ["metastore", "landing", "raw", "curated", "core", "mart", "reporting", "sharing"]
    replication_type = "LRS"
  }
  # Optional: additional accounts for domain separation
  "secure" = {
    containers       = ["pii", "health"]
    replication_type = "ZRS"
  }
}
```

Storage account names are constructed as: `{storage_account_prefix}{key}{6-char-random}`. Total length must not exceed 24 characters.

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| resource_group_name | Name of the resource group | string | Yes |
| location | Azure region | string | Yes |
| environment | Environment name (dev/prod) | string | Yes |
| storage_account_prefix | Prefix for storage account name (max 18 chars) | string | Yes |
| containers | List of container names to create | list(string) | Yes |
| databricks_access_connector_id | Databricks Access Connector ID for RBAC | string | Yes |
| account_tier | Storage account tier (Standard/Premium) | string | No |
| replication_type | Storage replication type | string | No |
| enable_private_endpoint | Enable private endpoint (requires VNet injection) | bool | No |
| private_endpoint_subnet_id | Subnet ID for private endpoint | string | Conditional |
| create_private_dns_zone | Create privatelink DNS zone and VNet link | bool | No |
| private_dns_zone_vnet_id | VNet ID for DNS zone link | string | Conditional |
| enable_lifecycle_policy | Enable automated Hot→Cool→Archive tiering | bool | No |
| lifecycle_containers | Containers to apply lifecycle to | list(string) | No |
| cool_after_days | Days until blob moves to Cool tier | number | No |
| archive_after_days | Days until blob moves to Archive tier | number | No |
| delete_after_days | Days until blob is deleted (0 = disabled) | number | No |
| tags | Resource tags | map(string) | No |

## Outputs

| Name | Description |
|------|-------------|
| storage_account_id | Storage account ID |
| storage_account_name | Storage account name |
| primary_dfs_endpoint | Primary DFS endpoint for ADLS Gen2 |
| containers | Map of container names to IDs |

## Lifecycle Management

Automated data tiering reduces costs for cold data. Configure per account inside the `storage_accounts` map:

```hcl
# infra/envs/prod/prod.tfvars
storage_accounts = {
  "lake" = {
    containers              = ["metastore", "raw", "curated", "mart"]
    enable_lifecycle_policy = true
    lifecycle_containers    = ["raw"]   # Raw data ages fastest
    cool_after_days         = 30
    archive_after_days      = 90
    delete_after_days       = 0         # 0 = never delete (safe for prod)
  }
}
```

The lifecycle policy creates one rule per container in `lifecycle_containers`.
Rules apply to all `blockBlob` types within the container path prefix.

## Private Endpoint

Requires `enable_vnet_injection = true`. Creates:

- `azurerm_private_endpoint` on the DFS sub-resource
- `azurerm_private_dns_zone` (`privatelink.dfs.core.windows.net`)
- `azurerm_private_dns_zone_virtual_network_link` to the provided VNet

Public network access is **automatically disabled** when `enable_private_endpoint = true`.

```hcl
# infra/envs/prod/prod.tfvars
enable_vnet_injection   = true   # Required prerequisite (root-level variable)
enable_private_endpoint = true   # Root-level variable; applies to all storage accounts
```

Set `create_private_dns_zone = false` if your organization manages DNS zones centrally
(e.g., Azure Private DNS Resolver hub pattern).

## Notes

⚠️ **Important Configuration Points:**

1. **Storage Account Naming**: Must be globally unique (3-24 chars, lowercase, alphanumeric)
2. **Hierarchical Namespace**: Always enabled for ADLS Gen2 (required for Unity Catalog)
3. **Account Tier**: Use Premium for high-throughput workloads
4. **Replication**: Choose based on DR requirements (LRS/ZRS/GRS)
5. **RBAC Roles**: The Databricks Access Connector receives `Storage Blob Data Contributor` role

## Storage Conventions

### Option 1: Medallion Architecture (Recommended for Lakeflow)

- `bronze` - Raw ingested data (Lakeflow Connect sources)
- `silver` - Cleansed, validated data (Lakeflow pipelines)
- `gold` - Aggregated, business-ready data (Lakeflow pipelines)

### Option 2: Enterprise Pattern

- `landing` - External data upload zone
- `raw` - Raw source data
- `curated` - Transformed, enriched data

### Special Containers

- `metastore` - Unity Catalog root storage
- `checkpoints` - Streaming checkpoints (optional)
- `logs` - Audit logs (optional)

## Further Reading

See [docs/guides/storage-accounts.md](../../../docs/guides/storage-accounts.md) for the full operator guide including:
- When to use multiple accounts
- Naming constraints and calculations
- Unity Catalog External Location integration
- State migration instructions (migrating from single-account setup)
- Troubleshooting
