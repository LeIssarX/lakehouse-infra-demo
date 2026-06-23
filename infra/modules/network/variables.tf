variable "resource_group_name" {
  description = "Name of the resource group where network resources will be created"
  type        = string
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
}

variable "vnet_name" {
  description = "Name of the Virtual Network"
  type        = string
  default     = "vnet-lakehouse"
}

variable "vnet_mode" {
  description = "'create' (new VNet + subnets) or 'existing' (reuse an existing VNet/subnets by name)."
  type        = string
  default     = "create"
  validation {
    condition     = contains(["create", "existing"], var.vnet_mode)
    error_message = "vnet_mode must be 'create' or 'existing'."
  }
}

variable "existing_vnet_name" {
  description = "Name of an existing VNet to reuse when vnet_mode = existing. Defaults to vnet_name."
  type        = string
  default     = null
}

variable "existing_vnet_resource_group_name" {
  description = "Resource group of the existing VNet when vnet_mode = existing. Defaults to the deployment resource group."
  type        = string
  default     = null
}

variable "vnet_address_space" {
  description = "Address space for the Virtual Network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "public_subnet_address_prefixes" {
  description = "Address prefixes for the public Databricks subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "private_subnet_address_prefixes" {
  description = "Address prefixes for the private Databricks subnet"
  type        = list(string)
  default     = ["10.0.2.0/24"]
}

variable "databricks_workspace_name" {
  description = "Name of the Databricks workspace (used for subnet naming)"
  type        = string
}

variable "nsg_name" {
  description = "Name of the Network Security Group (optional, will be auto-generated if not provided)"
  type        = string
  default     = null
}

variable "route_table_name" {
  description = "Name of the Route Table (optional, will be auto-generated if not provided)"
  type        = string
  default     = null
}

variable "enable_private_link" {
  description = "Enable Private Link for Databricks (requires additional configuration)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
