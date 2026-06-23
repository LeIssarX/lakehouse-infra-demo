variable "resource_group_name" {
  description = "Name of the resource group where storage will be created"
  type        = string
}

variable "location" {
  description = "Azure region where storage will be created"
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

variable "storage_account_prefix" {
  description = "Prefix for storage account name (will append random suffix). Max 18 characters, lowercase alphanumeric only. Example: 'dlhdev' or 'dlhprod'"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,18}$", var.storage_account_prefix))
    error_message = "Storage account prefix must be 3-18 characters, lowercase alphanumeric only."
  }
}

variable "account_mode" {
  description = "'create' (new ADLS Gen2 account) or 'existing' (reuse an account by name; containers assumed present)."
  type        = string
  default     = "create"
  validation {
    condition     = contains(["create", "existing"], var.account_mode)
    error_message = "account_mode must be 'create' or 'existing'."
  }
}

variable "existing_account_name" {
  description = "Name of an existing storage account to reuse when account_mode = existing."
  type        = string
  default     = null
}

variable "containers" {
  description = "List of container names to create for the 7-layer lakehouse architecture"
  type        = list(string)
  default = [
    "metastore", # Unity Catalog root storage
    "landing",   # Landing zone for external data
    "raw",       # Minimally processed raw data
    "curated",   # Cleaned, validated, enriched data
    "core",      # Canonical business entities
    "mart",      # Business aggregations and KPIs
    "reporting", # Reporting-ready views
    "sharing"    # External data products (Delta Sharing)
  ]
}

variable "account_tier" {
  description = "Storage account tier. Use 'Premium' for high-performance workloads, 'Standard' for general purpose."
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "Account tier must be Standard or Premium."
  }
}

variable "account_kind" {
  description = "Storage account kind. Use 'BlockBlobStorage' with Premium tier for best performance."
  type        = string
  default     = "StorageV2"
  validation {
    condition     = contains(["StorageV2", "BlockBlobStorage"], var.account_kind)
    error_message = "Account kind must be StorageV2 or BlockBlobStorage."
  }
}

variable "replication_type" {
  description = "Storage replication type. LRS=locally redundant, ZRS=zone redundant, GRS=geo redundant"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.replication_type)
    error_message = "Invalid replication type."
  }
}

variable "databricks_access_connector_id" {
  description = "Databricks Access Connector ID for Unity Catalog RBAC assignment"
  type        = string
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint for storage account. Requires VNet injection — set private_endpoint_subnet_id."
  type        = bool
  default     = false
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoint deployment (required when enable_private_endpoint = true)"
  type        = string
  default     = null
}

variable "create_private_dns_zone" {
  description = "Create a privatelink DNS zone and link it to the VNet. Set false if your org manages DNS zones centrally."
  type        = bool
  default     = true
}

variable "private_dns_zone_vnet_id" {
  description = "VNet ID to link the private DNS zone to (required when create_private_dns_zone = true)"
  type        = string
  default     = null
}

variable "enable_lifecycle_policy" {
  description = "Enable automated data tiering lifecycle policy (Hot → Cool → Archive)"
  type        = bool
  default     = false
}

variable "lifecycle_containers" {
  description = "Containers to apply lifecycle policy to. Defaults to raw (largest volume of raw data)."
  type        = list(string)
  default     = ["raw"]
}

variable "cool_after_days" {
  description = "Days since last modification before blob is tiered to Cool storage"
  type        = number
  default     = 30
  validation {
    condition     = var.cool_after_days >= 1
    error_message = "cool_after_days must be at least 1."
  }
}

variable "archive_after_days" {
  description = "Days since last modification before blob is tiered to Archive storage"
  type        = number
  default     = 90
  validation {
    condition     = var.archive_after_days >= 1
    error_message = "archive_after_days must be at least 1."
  }
}

variable "delete_after_days" {
  description = "Days since last modification before blob is deleted. Set to 0 to disable automatic deletion."
  type        = number
  default     = 365
  validation {
    condition     = var.delete_after_days >= 0
    error_message = "delete_after_days must be 0 (disabled) or a positive number."
  }
}

variable "enable_versioning" {
  description = "Enable blob versioning for data protection"
  type        = bool
  default     = false
}

variable "enable_soft_delete" {
  description = "Enable soft delete for containers and blobs"
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted blobs"
  type        = number
  default     = 7
  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365
    error_message = "Retention must be between 1 and 365 days."
  }
}

variable "tags" {
  description = "Tags to apply to all storage resources"
  type        = map(string)
  default     = {}
}
