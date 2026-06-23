locals {
  vnet_id            = local.is_create ? azurerm_virtual_network.main[0].id : data.azurerm_virtual_network.existing[0].id
  vnet_name_out      = local.is_create ? azurerm_virtual_network.main[0].name : data.azurerm_virtual_network.existing[0].name
  vnet_address_space = local.is_create ? azurerm_virtual_network.main[0].address_space : data.azurerm_virtual_network.existing[0].address_space
  public_subnet_id   = local.is_create ? azurerm_subnet.public[0].id : data.azurerm_subnet.existing_public[0].id
  public_subnet_nm   = local.is_create ? azurerm_subnet.public[0].name : data.azurerm_subnet.existing_public[0].name
  private_subnet_id  = local.is_create ? azurerm_subnet.private[0].id : data.azurerm_subnet.existing_private[0].id
  private_subnet_nm  = local.is_create ? azurerm_subnet.private[0].name : data.azurerm_subnet.existing_private[0].name
}

output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = local.vnet_id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = local.vnet_name_out
}

output "vnet_address_space" {
  description = "Address space of the Virtual Network"
  value       = local.vnet_address_space
}

output "public_subnet_id" {
  description = "ID of the public Databricks subnet"
  value       = local.public_subnet_id
}

output "public_subnet_name" {
  description = "Name of the public Databricks subnet"
  value       = local.public_subnet_nm
}

output "private_subnet_id" {
  description = "ID of the private Databricks subnet"
  value       = local.private_subnet_id
}

output "private_subnet_name" {
  description = "Name of the private Databricks subnet"
  value       = local.private_subnet_nm
}

output "nsg_id" {
  description = "ID of the Network Security Group (create mode only)"
  value       = local.is_create ? azurerm_network_security_group.main[0].id : null
}

output "nsg_name" {
  description = "Name of the Network Security Group (create mode only)"
  value       = local.is_create ? azurerm_network_security_group.main[0].name : null
}

output "route_table_id" {
  description = "ID of the Route Table (create mode only)"
  value       = local.is_create ? azurerm_route_table.main[0].id : null
}

output "route_table_name" {
  description = "Name of the Route Table (create mode only)"
  value       = local.is_create ? azurerm_route_table.main[0].name : null
}

output "public_nsg_association_id" {
  description = "ID of the public subnet NSG association (create mode only; existing subnets assumed pre-associated)"
  value       = local.is_create ? azurerm_subnet_network_security_group_association.public[0].id : null
}

output "private_nsg_association_id" {
  description = "ID of the private subnet NSG association (create mode only; existing subnets assumed pre-associated)"
  value       = local.is_create ? azurerm_subnet_network_security_group_association.private[0].id : null
}
