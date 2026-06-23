variable "workspace_url" {
  description = "Databricks workspace URL (for provider configuration)"
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

variable "enable_cluster_policies" {
  description = "Create cluster governance policies"
  type        = bool
  default     = true
}

variable "require_unity_catalog" {
  description = "Enforce Unity Catalog in all cluster policies"
  type        = bool
  default     = true
}

variable "require_serverless" {
  description = "Prefer serverless compute in policies (recommended for cost optimization)"
  type        = bool
  default     = true
}

variable "auto_termination_minutes" {
  description = "Default auto-termination time for interactive clusters (minutes)"
  type        = number
  default     = 30
  validation {
    condition     = var.auto_termination_minutes >= 10 && var.auto_termination_minutes <= 10000
    error_message = "Auto-termination must be between 10 and 10000 minutes."
  }
}

variable "max_cluster_lifetime_minutes" {
  description = "Maximum cluster lifetime (minutes). null = unlimited."
  type        = number
  default     = null
}

variable "allowed_node_types" {
  description = "List of allowed Azure VM node types. Empty list = all types allowed."
  type        = list(string)
  default = [
    "Standard_DS3_v2", # 4 cores, 14 GB RAM - General purpose
    "Standard_DS4_v2", # 8 cores, 28 GB RAM - General purpose
    "Standard_E8_v3",  # 8 cores, 64 GB RAM - Memory optimized
    "Standard_E16_v3"  # 16 cores, 128 GB RAM - Memory optimized
  ]
}

variable "enable_spot_instances" {
  description = "Allow spot instances in job policies (cost savings)"
  type        = bool
  default     = true
}

variable "max_workers_limit" {
  description = "Maximum number of workers for autoscaling. null = unlimited."
  type        = number
  default     = 10
}

variable "enable_token_policy" {
  description = "Configure PAT token management policy"
  type        = bool
  default     = true
}

variable "max_token_lifetime_days" {
  description = "Maximum PAT token lifetime in days (0 = unlimited, not recommended)"
  type        = number
  default     = 90
  validation {
    condition     = var.max_token_lifetime_days >= 0 && var.max_token_lifetime_days <= 365
    error_message = "Token lifetime must be between 0 and 365 days."
  }
}

variable "enable_ip_access_lists" {
  description = "Enable IP access list restrictions"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of allowed IP ranges (CIDR notation) for workspace access"
  type        = list(string)
  default     = []
}

variable "blocked_ip_ranges" {
  description = "List of blocked IP ranges (CIDR notation)"
  type        = list(string)
  default     = []
}

variable "policy_permissions" {
  description = "Map of group/user permissions for cluster policies"
  type = map(object({
    group_name        = optional(string, null)
    user_name         = optional(string, null)
    service_principal = optional(string, null)
    permission_level  = string # CAN_USE
  }))
  default = {}
}

variable "enable_enhanced_security" {
  description = "Enable enhanced security monitoring (Premium tier only)"
  type        = bool
  default     = true
}

variable "enable_automatic_cluster_updates" {
  description = "Enable automatic cluster updates (recommended)"
  type        = bool
  default     = true
}

variable "automatic_cluster_update_schedule" {
  description = "Schedule for automatic cluster updates"
  type = object({
    frequency   = string # FIRST_OF_MONTH, SECOND_OF_MONTH, etc.
    day_of_week = string # SUNDAY, MONDAY, etc.
    hour        = number # 0-23
    minute      = number # 0-59
  })
  default = {
    frequency   = "FIRST_OF_MONTH"
    day_of_week = "SUNDAY"
    hour        = 1
    minute      = 0
  }
}

variable "enable_ml_autologging" {
  description = "Enable automatic MLflow experiment tracking (enableDatabricksAutologging)"
  type        = bool
  default     = false
}

variable "enforce_user_isolation" {
  description = "Enforce Unity Catalog user isolation mode (each user runs in their own container)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to policies (where supported)"
  type        = map(string)
  default     = {}
}

# ==========================================================
# Policy Tuning
# ==========================================================

variable "spark_version" {
  description = "Default Databricks Runtime version used in cluster policies"
  type        = string
  default     = "auto:latest-lts"
}

variable "autotermination_min_floor" {
  description = "Minimum allowed autotermination (minutes) enforced across all cluster policies"
  type        = number
  default     = 10
}

variable "interactive_max_clusters_per_user" {
  description = "Maximum interactive clusters per user (typically higher in dev, lower in prod)"
  type        = number
  default     = 5
}

variable "job_max_clusters_per_user" {
  description = "Maximum job clusters per user"
  type        = number
  default     = 10
}

variable "job_autotermination_minutes" {
  description = "Fixed autotermination time for job clusters (minutes)"
  type        = number
  default     = 15
}

variable "ml_max_clusters_per_user" {
  description = "Maximum ML clusters per user"
  type        = number
  default     = 3
}

variable "ml_spark_version" {
  description = "Default Databricks Runtime version for ML cluster policy"
  type        = string
  default     = "auto:latest-ml"
}

variable "ml_allowed_node_types" {
  description = "Allowed Azure VM node types for ML clusters"
  type        = list(string)
  default = [
    "Standard_DS4_v2",
    "Standard_E8_v3",
    "Standard_E16_v3"
  ]
}

variable "ml_autotermination_min" {
  description = "Minimum allowed autotermination for ML clusters (minutes)"
  type        = number
  default     = 30
}

variable "ml_autotermination_max" {
  description = "Maximum allowed autotermination for ML clusters (minutes)"
  type        = number
  default     = 180
}

variable "ml_autotermination_default" {
  description = "Default autotermination for ML clusters (minutes)"
  type        = number
  default     = 60
}

variable "pipeline_max_workers" {
  description = "Maximum autoscale workers for Lakeflow/DLT pipeline clusters"
  type        = number
  default     = 10
}
