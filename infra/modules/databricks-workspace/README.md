# Databricks Workspace Module

This module creates Azure Databricks workspaces with Unity Catalog support and modern security features.

## Deployment Modes

### Managed Instance (Default)

By default, the workspace is deployed as a managed instance (no VNet Injection). This is sufficient for most customers and provides fast provisioning and easy management.

### VNet Injection (Optional)

VNet Injection can be enabled if advanced network security or integration into existing network infrastructure is required. This is controlled via the `enable_vnet_injection` variable.

**Migration:** Migration from managed to VNet Injection is possible at any time. See section "Migration & Options" below.

## Features

- **Databricks Premium SKU** with Unity Catalog support
- **Managed Identity (Access Connector)** for Unity Catalog authentication
- **VNet Injection** support (optional)
- **Enhanced Security & Compliance** settings
- **Serverless** compute support
- **Private Link** ready
- Automatic cluster updates configuration
- Workspace-level settings and features

## Architecture

```text
Databricks Workspace (Premium)
├── Access Connector (Managed Identity)
├── Unity Catalog enabled
├── Serverless SQL/Compute enabled
├── Enhanced Security Monitoring
└── VNet Injection (optional)
```

## Resources Created

- `azurerm_databricks_workspace` - Databricks workspace
- `azurerm_databricks_access_connector` - Managed identity for Unity Catalog
- `databricks_mws_workspaces` (optional) - For E2 architecture
- Workspace settings (via Databricks provider)

## Usage

### Standard Deployment (Single Environment)

```hcl
module "databricks_workspace" {
  source = "../../modules/databricks-workspace"

  resource_group_name = var.resource_group_name
  location            = var.location
  environment         = "dev"
  
  workspace_name      = "dbw-lakehouse-dev"
  sku                 = "premium"
  
  # VNet injection (optional)
  enable_vnet_injection = false
  public_subnet_name      = module.network.public_subnet_name
  private_subnet_name     = module.network.private_subnet_name
  virtual_network_id      = module.network.vnet_id
  
  # Modern features
  enable_serverless_compute = true
  enable_unity_catalog      = true
  
  tags = var.tags
}
```

### Managed Instance (Default)

```hcl
module "databricks_workspace" {
  source = "../../modules/databricks-workspace"
  resource_group_name = var.resource_group_name
  location            = var.location
  environment         = "dev"
  workspace_name      = "dbw-lakehouse-dev"
  sku                 = "premium"
  # VNet Injection NICHT aktivieren
  enable_vnet_injection = false
  # Modern features
  enable_serverless_compute = true
  enable_unity_catalog      = true
  tags = var.tags
}
```

### VNet Injection (Optional)

```hcl
module "databricks_workspace" {
  source = "../../modules/databricks-workspace"
  resource_group_name = var.resource_group_name
  location            = var.location
  environment         = "dev"
  workspace_name      = "dbw-lakehouse-dev"
  sku                 = "premium"
  enable_vnet_injection   = true
  public_subnet_name      = module.network.public_subnet_name
  private_subnet_name     = module.network.private_subnet_name
  virtual_network_id      = module.network.vnet_id
  enable_serverless_compute = true
  enable_unity_catalog      = true
  tags = var.tags
}
```

### Multi-Environment Pattern (Dev + Prod)

```hcl
// Dev Workspace
module "databricks_dev" {
  source = "../../modules/databricks-workspace"
  
  workspace_name = "dbw-lakehouse-dev"
  environment    = "dev"
  # ... other settings
}

// Prod Workspace
module "databricks_prod" {
  source = "../../modules/databricks-workspace"
  
  workspace_name = "dbw-lakehouse-prod"
  environment    = "prod"
  # ... other settings
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| resource_group_name | Name of the resource group | string | Yes |
| location | Azure region | string | Yes |
| environment | Environment (dev/prod/sandbox) | string | Yes |
| workspace_name | Databricks workspace name | string | Yes |
| sku | Databricks SKU (standard/premium/trial) | string | Yes |
| enable_unity_catalog | Enable Unity Catalog features | bool | No (default: true) |
| enable_serverless_compute | Enable serverless SQL/compute | bool | No (default: true) |
| enable_vnet_injection | Use custom VNet | bool | No (default: false) |
| public_subnet_name | Public subnet name (if VNet injection) | string | Conditional |
| private_subnet_name | Private subnet name (if VNet injection) | string | Conditional |
| virtual_network_id | VNet ID (if custom VNet) | string | Conditional |
| enable_enhanced_security | Enable enhanced security monitoring | bool | No (default: true) |
| tags | Resource tags | map(string) | No |

## Outputs

| Name | Description |
|------|-------------|
| workspace_id | Databricks workspace ID |
| workspace_url | Databricks workspace URL |
| access_connector_id | Access Connector principal ID (for RBAC) |
| access_connector_principal_id | Access Connector principal ID |

## Modern Features

### ✅ Serverless Compute

- **Serverless SQL warehouses** - No cluster management
- **Serverless workflows** - On-demand compute for jobs
- **Instant startup** - No cold start delays

### ✅ Unity Catalog

- **Centralized governance** - Single source of truth
- **Fine-grained access control** - Column/row-level security
- **Data lineage** - Automatic tracking
- **Delta Sharing** - Secure data sharing

### ✅ Lakeflow Support

- **Lakeflow Pipelines** - Next-gen DLT with improved UI
- **Lakeflow Connect** - Native connectors for data sources
- **Auto-optimization** - AI-driven optimizations

### ✅ Enhanced Security

- **Compliance profiles** - PCI-DSS, HIPAA ready
- **Security monitoring** - Threat detection
- **IP access lists** - Network security
- **Private Link** - Private connectivity

## Configuration Notes

⚠️ **TODO: Configure these after deployment**

## Migration & Optionen

### Wann managed Instanz verwenden?

- Für schnelle Bereitstellung und einfache Verwaltung
- Wenn keine speziellen Netzwerkanforderungen bestehen
- Standard für die meisten Kunden

### Wann VNet Injection aktivieren?

- Wenn Integration in bestehende Netzwerkinfrastruktur notwendig ist
- Für erweiterte Netzwerksicherheit (z.B. Private Link, NSG, IP-Whitelisting)
- Bei Compliance-Anforderungen

### Migration von managed zu VNet Injection

1. Setze `enable_vnet_injection = true` im Modul.
2. Definiere die Subnet- und VNet-Parameter (`public_subnet_name`, `private_subnet_name`, `virtual_network_id`).
3. Führe Terraform Apply aus.
4. Workspace wird migriert, bestehende Daten und Einstellungen bleiben erhalten.

Siehe [docs/databricks-vnet-injection-migration.md](../../docs/databricks-vnet-injection-migration.md) für detaillierte Schritte.

⚠️ **TODO: Configure these after deployment**

1. **Account-Level Unity Catalog Setup**
   - Create metastore at account level
   - Assign metastore to workspace
   - Configure storage credentials

2. **Workspace Settings**
   - IP access lists (if required)
   - Token policies
   - Secret scopes

3. **Network Security**
   - NSG rules for Databricks control plane
   - Private endpoints (if using Private Link)

## Post-Deployment Steps

After workspace creation:

```bash
# Configure Databricks CLI
databricks configure --token \
  --host https://<workspace-url>

# Verify serverless is enabled
databricks settings get-serverless-compute

# Create SQL warehouse (serverless)
databricks sql warehouses create \
  --name "Serverless Warehouse" \
  --cluster-size "X-Small" \
  --enable-serverless-compute true
```
