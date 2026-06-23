variable "environment" {
  description = "Environment name (dev, prod, sandbox)"
  type        = string
  validation {
    condition     = contains(["dev", "prod", "sandbox"], var.environment)
    error_message = "Environment must be dev, prod, or sandbox."
  }
}

variable "name" {
  description = "Logical name for this cluster. Combined with environment to form the cluster display name."
  type        = string
}

variable "cluster_policy_id" {
  description = "ID of the cluster policy to apply to the interactive cluster (from governance module)"
  type        = string
}

variable "owner" {
  description = "Email of the user set as single-user owner of the interactive cluster"
  type        = string
}

variable "node_type" {
  description = "Azure VM node type for the interactive cluster driver and workers"
  type        = string
  default     = "Standard_DS4_v2"
}

variable "min_workers" {
  description = "Minimum number of autoscale workers for the interactive cluster"
  type        = number
  default     = 1
}

variable "max_workers" {
  description = "Maximum number of autoscale workers for the interactive cluster"
  type        = number
  default     = 4
}

variable "auto_termination_minutes" {
  description = "Idle time before the cluster auto-terminates (minutes)"
  type        = number
  default     = 30
  validation {
    condition     = var.auto_termination_minutes >= 10 && var.auto_termination_minutes <= 10000
    error_message = "Auto-termination must be between 10 and 10000 minutes."
  }
}

variable "enable_spot_instances" {
  description = "Use SPOT_WITH_FALLBACK_AZURE availability for cost savings; ON_DEMAND_AZURE when false"
  type        = bool
  default     = true
}

variable "spark_version" {
  description = "Databricks Runtime version for the interactive cluster (e.g. 'auto:latest-lts', '15.4.x-scala2.12')"
  type        = string
  default     = "auto:latest-lts"
}

variable "data_security_mode" {
  description = "Unity Catalog data security mode for the interactive cluster (SINGLE_USER or USER_ISOLATION)"
  type        = string
  default     = "SINGLE_USER"
}

variable "runtime_engine" {
  description = "Cluster runtime engine. STANDARD or PHOTON — the shared_interactive policy defaults to STANDARD."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "PHOTON"], var.runtime_engine)
    error_message = "runtime_engine must be STANDARD or PHOTON."
  }
}

variable "tags" {
  description = "Tags to apply to cluster custom_tags"
  type        = map(string)
  default     = {}
}
