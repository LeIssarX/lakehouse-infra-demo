variable "resource_group_name" {
  description = "Name of the resource group where Key Vault will be created"
  type        = string
}

variable "location" {
  description = "Azure region where Key Vault will be created"
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

variable "key_vault_name" {
  description = "Name of the Key Vault (optional, will be auto-generated if not provided). Must be 3-24 characters, alphanumeric and hyphens."
  type        = string
  default     = null
  validation {
    condition     = var.key_vault_name == null || can(regex("^[a-zA-Z0-9-]{3,24}$", var.key_vault_name))
    error_message = "Key Vault name must be 3-24 characters, alphanumeric and hyphens only."
  }
}

variable "sku_name" {
  description = "SKU for Key Vault (standard or premium). Premium includes HSM-backed keys."
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "SKU must be standard or premium."
  }
}

variable "tenant_id" {
  description = "Azure AD tenant ID. If not provided, will use current tenant from Azure CLI."
  type        = string
  default     = null
}

variable "enable_rbac_authorization" {
  description = "Use RBAC for access control instead of access policies (recommended)"
  type        = bool
  default     = true
}

variable "rbac_assignments" {
  description = "Map of RBAC role assignments. Key is assignment name, value is object with principal_id and role."
  type = map(object({
    principal_id = string
    role         = string # e.g., "Key Vault Administrator", "Key Vault Secrets User"
  }))
  default = {}
}

variable "enable_public_access" {
  description = "Enable public network access. Set to false for private endpoint only."
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of allowed IP ranges in CIDR notation (if public access is enabled)"
  type        = list(string)
  default     = []
}

variable "enable_soft_delete" {
  description = "Enable soft delete for Key Vault (recommended for production)"
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted items (7-90)"
  type        = number
  default     = 7
  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention must be between 7 and 90 days."
  }
}

variable "enable_purge_protection" {
  description = "Enable purge protection (cannot be disabled once enabled - use with caution)"
  type        = bool
  default     = false
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logging to Log Analytics"
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostic logs (required if enable_diagnostic_logs is true)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to Key Vault resources"
  type        = map(string)
  default     = {}
}
