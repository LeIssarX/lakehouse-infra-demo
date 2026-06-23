# Network Module

This module creates the Azure Virtual Network infrastructure required for Databricks with Private Link support.

## Features

- Virtual Network with customizable address space
- Public and Private subnets with Databricks delegation
- Network Security Groups (NSGs)
- Route Tables
- Private DNS Zones (optional)
- Support for Databricks VNet Injection

## Resources Created

- `azurerm_virtual_network` - Main VNet
- `azurerm_subnet` (public & private) - Databricks subnets with delegation
- `azurerm_network_security_group` - Network security
- `azurerm_route_table` - Custom routing
- `azurerm_subnet_network_security_group_association` - NSG associations
- `azurerm_subnet_route_table_association` - Route table associations

## Architecture

```text
VNet (10.0.0.0/16)
├── Public Subnet (10.0.1.0/24)
│   └── Databricks Public Subnet (requires delegation)
└── Private Subnet (10.0.2.0/24)
    └── Databricks Private Subnet (requires delegation)
```

## Usage

```hcl
module "network" {
  source = "../../modules/network"

  resource_group_name         = var.resource_group_name
  location                    = var.location
  vnet_name                   = "vnet-lakehouse-${var.environment}"
  vnet_address_space          = ["10.0.0.0/16"]
  public_subnet_address_prefixes  = ["10.0.1.0/24"]
  private_subnet_address_prefixes = ["10.0.2.0/24"]
  databricks_workspace_name   = var.databricks_workspace_name
  
  tags = var.tags
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| resource_group_name | Name of the resource group | string | Yes |
| location | Azure region | string | Yes |
| vnet_name | Name of the Virtual Network | string | Yes |
| vnet_address_space | Address space for VNet | list(string) | Yes |
| public_subnet_address_prefixes | Public subnet CIDR | list(string) | Yes |
| private_subnet_address_prefixes | Private subnet CIDR | list(string) | Yes |
| databricks_workspace_name | Databricks workspace name (for subnet naming) | string | Yes |
| nsg_name | NSG name (optional) | string | No |
| route_table_name | Route table name (optional) | string | No |
| tags | Resource tags | map(string) | No |

## Outputs

| Name | Description |
|------|-------------|
| vnet_id | ID of the Virtual Network |
| vnet_name | Name of the Virtual Network |
| public_subnet_id | ID of the public subnet |
| private_subnet_id | ID of the private subnet |
| nsg_id | ID of the Network Security Group |

## Notes

- Databricks requires specific subnet delegation to `Microsoft.Databricks/workspaces`
- NSG rules should allow Databricks control plane communication
- For Private Link, additional private endpoints need to be created separately
