variable "resource_group_name" {
  description = "Name of the resource group where Databricks workspace will be created"
  type        = string
}

variable "workspace_mode" {
  description = "'create' (new workspace) or 'existing' (reuse a workspace by name in the resource group)."
  type        = string
  default     = "create"
  validation {
    condition     = contains(["create", "existing"], var.workspace_mode)
    error_message = "workspace_mode must be 'create' or 'existing'."
  }
}

variable "location" {
  description = "Azure region where the workspace will be created"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, sandbox)"
  type        = string
  validation {
    condition     = contains(["dev", "prod", "sandbox"], var.environment)
    error_message = "Environment must be dev, prod, or sandbox."
  }
}

variable "workspace_name" {
  description = "Name of the Databricks workspace"
  type        = string
}

variable "sku" {
  description = "The SKU for the Databricks workspace (standard, premium, or trial). Premium required for Unity Catalog."
  type        = string
  default     = "premium"
  validation {
    condition     = contains(["standard", "premium", "trial"], var.sku)
    error_message = "SKU must be standard, premium, or trial."
  }
}

variable "enable_unity_catalog" {
  description = "Enable Unity Catalog features (requires premium SKU)"
  type        = bool
  default     = true
}

variable "enable_serverless_compute" {
  description = "Enable serverless SQL warehouses and workflows"
  type        = bool
  default     = true
}

variable "enable_vnet_injection" {
  description = "Deploy workspace with custom VNet (VNet injection)"
  type        = bool
  default     = false
}

variable "public_subnet_name" {
  description = "Name of the public subnet for VNet injection (required if enable_vnet_injection is true)"
  type        = string
  default     = null
}

variable "private_subnet_name" {
  description = "Name of the private subnet for VNet injection (required if enable_vnet_injection is true)"
  type        = string
  default     = null
}

variable "virtual_network_id" {
  description = "ID of the virtual network for VNet injection (required if enable_vnet_injection is true)"
  type        = string
  default     = null
}

variable "public_nsg_association_id" {
  description = "ID of the public subnet NSG association (required for VNet injection)"
  type        = string
  default     = null
}

variable "private_nsg_association_id" {
  description = "ID of the private subnet NSG association (required for VNet injection)"
  type        = string
  default     = null
}

variable "enable_enhanced_security" {
  description = "Enable enhanced security monitoring and compliance features"
  type        = bool
  default     = true
}

variable "enable_automatic_cluster_updates" {
  description = "Enable automatic cluster updates (recommended)"
  type        = bool
  default     = true
}

variable "enable_compliance_profile" {
  description = "Enable compliance security profile (HIPAA, PCI-DSS)"
  type        = bool
  default     = false
}

variable "compliance_standards" {
  description = "List of compliance standards to enable (e.g., ['HIPAA', 'PCI_DSS'])"
  type        = list(string)
  default     = []
}

variable "managed_resource_group_name" {
  description = "Name of the managed resource group (optional, will be auto-generated if not provided)"
  type        = string
  default     = null
}

variable "public_network_access_enabled" {
  description = "Enable public network access (set to false for Private Link only)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all Databricks resources"
  type        = map(string)
  default     = {}
}
