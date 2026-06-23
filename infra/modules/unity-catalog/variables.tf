variable "workspace_id" {
  description = "Azure resource ID of the Databricks workspace (for metastore assignment)"
  type        = string
}

variable "databricks_workspace_id" {
  description = "Numeric Databricks workspace ID (for workspace bindings)"
  type        = string
  default     = null
}

variable "workspace_url" {
  description = "Databricks workspace URL (for provider configuration)"
  type        = string
}

variable "create_metastore" {
  description = "Whether to create a new metastore (true) or use existing (false)"
  type        = bool
  default     = false
}

variable "use_workspace_metastore" {
  description = "Whether to auto-discover and use the workspace's existing metastore (for Auto-UC workspaces deployed after Nov 9, 2023)"
  type        = bool
  default     = true
}

variable "assign_metastore_to_workspace" {
  description = "Whether to assign metastore to workspace. Set to false for Auto-UC workspaces (already assigned)."
  type        = bool
  default     = false
}

variable "metastore_id" {
  description = "Existing metastore ID (required if create_metastore is false and use_workspace_metastore is false)"
  type        = string
  default     = null
}

variable "metastore_name" {
  description = "Name of the Unity Catalog metastore (required if creating new metastore)"
  type        = string
  default     = null
}

variable "storage_root" {
  description = "Root storage location for metastore (abfss:// URL, required if creating new metastore)"
  type        = string
  default     = null
}

variable "region" {
  description = "Azure region for metastore (required if creating new metastore)"
  type        = string
  default     = null
}

variable "access_connector_id" {
  description = "Databricks Access Connector ID for storage credential"
  type        = string
}

variable "catalog_name" {
  description = "Name of the Unity Catalog catalog to create"
  type        = string
}
variable "catalog_storage_root" {
  description = "Storage root for catalog-level managed storage (abfss:// URL). Required for Auto-UC metastores with Default Storage."
  type        = string
  default     = null
}
variable "catalog_isolation_mode" {
  description = "Isolation mode for catalog (OPEN or ISOLATED). ISOLATED recommended for production."
  type        = string
  default     = "ISOLATED"
  validation {
    condition     = contains(["OPEN", "ISOLATED"], var.catalog_isolation_mode)
    error_message = "Isolation mode must be OPEN or ISOLATED."
  }
}

variable "external_locations" {
  description = <<-EOT
    Map of external location names to storage root URLs.

    Supported URL schemes:
      - Azure Data Lake Storage Gen2:  abfss://<container>@<account>.dfs.core.windows.net/<path>
      - Amazon S3:                     s3://<bucket>/<path>

    Each external location registers a root path in Unity Catalog and allows
    Databricks to create EXTERNAL tables and EXTERNAL volumes that read/write
    data at that path (or below it).

    Important: all locations in this map share the same storage credential
    (access_connector_id). For locations requiring a different credential,
    create a separate module instance.

    Example:
      external_locations = {
        bronze = "abfss://bronze@mystorageaccount.dfs.core.windows.net/"
        silver = "abfss://silver@mystorageaccount.dfs.core.windows.net/"
      }
  EOT
  type        = map(string)
  default     = {}
}

variable "schemas" {
  description = "Map of schema configurations. Each schema can have comment and volumes."
  type = map(object({
    comment = optional(string, "Managed by Terraform")
    volumes = optional(map(object({
      type    = string # MANAGED or EXTERNAL
      comment = optional(string, "Managed by Terraform")
      path    = optional(string, null) # For EXTERNAL volumes only
    })), {})
  }))
  default = {}
}

variable "owner_principal" {
  description = "Principal (user/group/service principal) to set as owner of catalog and schemas. Leave null for current user."
  type        = string
  default     = null
}

variable "cicd_sp_application_id" {
  description = "Azure AD Application (client) ID of the CI/CD Service Principal. When set, grants ALL_PRIVILEGES on the storage credential and all external locations so the SP can manage them during tofu plan/apply."
  type        = string
  default     = null
}

variable "catalog_grants" {
  description = "Map of catalog-level grant configurations"
  type = map(object({
    principal  = string
    privileges = list(string)
  }))
  default = {}
}

variable "schema_grants" {
  description = "Map of schema names to their grant configurations"
  type = map(map(object({
    principal  = string
    privileges = list(string)
  })))
  default = {}
}

variable "enable_system_tables" {
  description = "Enable Unity Catalog system tables for audit, lineage, and billing. NOTE: Unity Catalog auto-provisions system schemas; this only controls whether OpenTofu manages them explicitly. Disable for local dev (Databricks TF provider v1.112 has a known bug creating system_schema resources via workspace PATs)."
  type        = bool
  default     = false
}

variable "system_table_schemas" {
  description = "List of system schemas to enable via the EnableSystemSchema API. Valid values: access, billing, query, compute. Note: lineage is enabled automatically by Unity Catalog and cannot be explicitly enabled via this API."
  type        = list(string)
  default     = ["access", "billing", "query"]
}

variable "enable_predictive_optimization" {
  description = "Enable predictive optimization for tables (auto-optimize, auto-compaction)"
  type        = bool
  default     = true
}

variable "enable_workspace_binding" {
  description = "Enable workspace binding for ISOLATED mode resources"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to Unity Catalog resources (where supported)"
  type        = map(string)
  default     = {}
}
