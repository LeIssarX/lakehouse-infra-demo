# ==========================================================
# Variables
# ==========================================================
# Values are provided via (in order):
#   1. infra/common.tfvars   — global, shared across environments
#   2. infra/envs/{env}/{env}.tfvars — environment-specific overrides
#
# Usage:
#   tofu plan -var-file=common.tfvars -var-file=envs/dev/dev.tfvars

# ==========================================================
# Environment Configuration
# ==========================================================

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "bootstrap_mode" {
  description = "Bootstrap mode: skip RBAC-dependent data sources during first deployment. Set to true for greenfield, false for updates."
  type        = bool
  default     = false
}

# ==========================================================
# Azure Configuration
# ==========================================================

variable "subscription_id" {
  description = "Azure Subscription ID. Used to construct the Databricks workspace resource ID for provider authentication."
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "germanywestcentral"
}

variable "resource_group_name" {
  description = "Name of the resource group (created when resource_group_mode = create)"
  type        = string
}

variable "resource_group_mode" {
  description = "Resource group mode: 'create' (new RG named resource_group_name) or 'existing' (reuse an existing RG by name)."
  type        = string
  default     = "create"
  validation {
    condition     = contains(["create", "existing"], var.resource_group_mode)
    error_message = "resource_group_mode must be 'create' or 'existing'."
  }
}

variable "existing_resource_group_name" {
  description = "Name of an existing resource group to reuse when resource_group_mode = existing. Defaults to resource_group_name."
  type        = string
  default     = null
}

# ==========================================================
# Databricks Configuration
# ==========================================================

variable "databricks_account_id" {
  description = "Databricks Account ID. Required for AIM and account-level features. Find at: https://accounts.azuredatabricks.net/ → Settings → Account ID."
  type        = string
  default     = null
}

variable "databricks_workspace_name" {
  description = "Name of the Databricks workspace (created when databricks_workspace_mode = create)"
  type        = string
}

variable "databricks_workspace_mode" {
  description = "Workspace mode: 'create' (new workspace) or 'existing' (attach to an existing workspace by name in the resource group)."
  type        = string
  default     = "create"
  validation {
    condition     = contains(["create", "existing"], var.databricks_workspace_mode)
    error_message = "databricks_workspace_mode must be 'create' or 'existing'."
  }
}

# ==========================================================
# Workspace Configuration
# ==========================================================

variable "workspace_sku" {
  description = "Databricks workspace SKU (premium or trial)"
  type        = string
  default     = "premium"
}

variable "enable_unity_catalog" {
  description = "Enable Unity Catalog on the workspace"
  type        = bool
  default     = true
}

variable "enable_serverless_compute" {
  description = "Enable serverless compute on the workspace"
  type        = bool
  default     = true
}

# ==========================================================
# Observability Configuration
# ==========================================================

variable "log_retention_days" {
  description = "Log Analytics workspace retention in days (30 = dev, 90 = prod compliance)"
  type        = number
  default     = 30
}

# ==========================================================
# Unity Catalog Configuration
# ==========================================================

variable "catalog_name" {
  description = "Name of the Unity Catalog catalog for this environment"
  type        = string
}

variable "catalog_schemas" {
  description = "Schema definitions for the Unity Catalog catalog (7-layer architecture)."
  type = map(object({
    comment = optional(string, "Managed by OpenTofu")
    volumes = optional(map(object({
      type    = string
      comment = optional(string, "Managed by OpenTofu")
      path    = optional(string, null)
    })), {})
  }))
  default = {}
}

variable "catalog_isolation_mode" {
  description = "Unity Catalog isolation mode (ISOLATED or OPEN)"
  type        = string
  default     = "ISOLATED"
}

variable "unity_catalog_metastore_mode" {
  description = "Metastore configuration mode: 'auto' (workspace metastore), 'create' (new metastore), 'existing' (use existing by ID)"
  type        = string
  default     = "auto"
  validation {
    condition     = contains(["auto", "create", "existing"], var.unity_catalog_metastore_mode)
    error_message = "Metastore mode must be 'auto', 'create', or 'existing'."
  }
}

variable "unity_catalog_metastore_id" {
  description = "Existing Unity Catalog Metastore ID (optional manual override when metastore_mode = 'existing'). Typically left null — prod retrieves the ID automatically from dev's remote state."
  type        = string
  default     = null
}

variable "unity_catalog_metastore_name" {
  description = "Name for new Unity Catalog Metastore (required when metastore_mode = 'create')"
  type        = string
  default     = null
}

# ==========================================================
# Remote State: Dev (for shared metastore — prod only)
# ==========================================================
# Prod reads dev's state to get the shared regional metastore ID.
# Leave all dev_remote_state_* variables null in dev.tfvars.

variable "dev_remote_state_resource_group" {
  description = "Resource group of the dev state storage account (set in prod.tfvars only)"
  type        = string
  default     = null
}

variable "dev_remote_state_storage_account" {
  description = "Storage account name for dev's remote state (set in prod.tfvars only)"
  type        = string
  default     = null
}

variable "dev_remote_state_container" {
  description = "Container name for dev's remote state (set in prod.tfvars only)"
  type        = string
  default     = "tfstate"
}

variable "dev_remote_state_key" {
  description = "Blob key for dev's remote state file (set in prod.tfvars only)"
  type        = string
  default     = "dev.terraform.tfstate"
}

# ==========================================================
# Network Configuration
# ==========================================================

variable "enable_vnet_injection" {
  description = "Deploy Databricks with custom VNet (VNet injection)"
  type        = bool
  default     = false
}

variable "vnet_name" {
  description = "Name of the Virtual Network"
  type        = string
  default     = null
}

variable "vnet_mode" {
  description = "VNet mode (only relevant when enable_vnet_injection = true): 'create' (new VNet + subnets) or 'existing' (reuse an existing VNet/subnets by name)."
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
  description = "Address prefixes for public Databricks subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "private_subnet_address_prefixes" {
  description = "Address prefixes for private Databricks subnet"
  type        = list(string)
  default     = ["10.0.2.0/24"]
}

variable "enable_public_access" {
  description = "Enable public network access (disable for production with Private Link)"
  type        = bool
  default     = true
}

# ==========================================================
# Storage Configuration
# ==========================================================

variable "storage_account_prefix" {
  description = "Prefix for storage account names (max 11 chars, lowercase alphanumeric). Combined with account key and random suffix: {prefix}{key}{random}. Total max 24 chars."
  type        = string
}

variable "storage_account_mode" {
  description = "Storage mode: 'create' (new ADLS Gen2 account(s)) or 'existing' (reuse an existing account by name; containers are created if missing)."
  type        = string
  default     = "create"
  validation {
    condition     = contains(["create", "existing"], var.storage_account_mode)
    error_message = "storage_account_mode must be 'create' or 'existing'."
  }
}

variable "existing_storage_account_name" {
  description = "Name of an existing ADLS Gen2 storage account to reuse when storage_account_mode = existing (applies to the 'lake' account)."
  type        = string
  default     = null
}

variable "storage_accounts" {
  description = <<-EOT
    ADLS Gen2 storage accounts to create. Key = logical name used in naming and Unity Catalog external locations.
    The "lake" key is required — it serves as the Unity Catalog Metastore root storage.
    Additional accounts can be added for domain separation or billing isolation.

    Example:
      storage_accounts = {
        "lake"   = {}                                          # all defaults
        "secure" = { containers = ["pii"], replication_type = "ZRS" }
      }
  EOT
  type = map(object({
    containers                 = optional(list(string), ["metastore", "landing", "raw", "curated", "core", "mart", "reporting", "sharing"])
    account_tier               = optional(string, "Standard")
    replication_type           = optional(string, "LRS")
    enable_lifecycle_policy    = optional(bool, false)
    lifecycle_containers       = optional(list(string), ["raw"])
    cool_after_days            = optional(number, 30)
    archive_after_days         = optional(number, 90)
    delete_after_days          = optional(number, 365)
    enable_soft_delete         = optional(bool, true)
    soft_delete_retention_days = optional(number, 7)
  }))
  default = {
    "lake" = {}
  }
  validation {
    condition     = contains(keys(var.storage_accounts), "lake")
    error_message = "storage_accounts must contain a 'lake' key — this account serves as the Unity Catalog Metastore root storage."
  }
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint for storage account (requires enable_vnet_injection = true)"
  type        = bool
  default     = false
}

# ==========================================================
# Key Vault Configuration
# ==========================================================

variable "key_vault_name" {
  description = "Name of the Key Vault (optional, will be auto-generated if not provided)"
  type        = string
  default     = null
}

variable "key_vault_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault secrets"
  type        = number
  default     = 7
}

variable "enable_purge_protection" {
  description = "Enable purge protection on Key Vault (prevents permanent deletion — required for prod)"
  type        = bool
  default     = false
}

variable "key_vault_allowed_ips" {
  description = "Allowed IP ranges for Key Vault access (CIDR notation)"
  type        = list(string)
  default     = []
}

# ==========================================================
# Governance Configuration
# ==========================================================

variable "auto_termination_minutes" {
  description = "Auto-terminate idle clusters after N minutes"
  type        = number
  default     = 30
}

variable "max_cluster_lifetime_minutes" {
  description = "Maximum cluster lifetime in minutes (null = unlimited)"
  type        = number
  default     = null
}

variable "max_workers_limit" {
  description = "Maximum workers per cluster"
  type        = number
  default     = 10
}

variable "enable_spot_instances" {
  description = "Enable spot/preemptible instances for cost savings"
  type        = bool
  default     = true
}

variable "max_token_lifetime_days" {
  description = "Maximum PAT token lifetime in days"
  type        = number
  default     = 90
}

variable "allowed_node_types" {
  description = "Allowed Azure VM node types for clusters"
  type        = list(string)
  default = [
    "Standard_DS3_v2",
    "Standard_DS4_v2",
    "Standard_E8_v3"
  ]
}

variable "enable_ip_access_lists" {
  description = "Enable IP allowlisting for workspace access"
  type        = bool
  default     = false
}

variable "governance_allowed_ips" {
  description = "Allowed IP ranges for workspace access (CIDR notation)"
  type        = list(string)
  default     = []
}

# ==========================================================
# Identity: AIM Groups
# ==========================================================
# Azure AD groups to create and sync to Databricks.
# Defined per environment in dev.tfvars / prod.tfvars.
# See: docs/guides/aim-setup.md

variable "aim_groups" {
  description = "Azure AD security groups to create and sync to Databricks via AIM."
  type = map(object({
    display_name               = string
    description                = string
    mail_nickname              = string
    allow_cluster_create       = optional(bool, false)
    allow_instance_pool_create = optional(bool, false)
  }))
  default = {}
}

variable "aim_group_ids" {
  description = "Pre-created Azure AD group object IDs (key → object_id). Set by the wizard via scripts/create-azure-groups.sh. When non-empty, Terraform references the groups by ID without any Azure AD API calls — eliminating the Group.ReadWrite.All permission requirement for the CI/CD service principal. Populated in identity.tfvars."
  type        = map(string)
  default     = {}
}

# ==========================================================
# Unity Catalog Grants
# ==========================================================

variable "catalog_grants" {
  description = "Catalog-level Unity Catalog grants. Key is an arbitrary label."
  type = map(object({
    principal  = string
    privileges = list(string)
  }))
  default = {}
}

variable "schema_grants" {
  description = "Schema-level Unity Catalog grants. Outer key = schema name, inner key = arbitrary label."
  type = map(map(object({
    principal  = string
    privileges = list(string)
  })))
  default = {}
}

variable "system_schema_grants" {
  description = "Grants on Unity Catalog system schemas. Outer key = schema name, inner key = arbitrary label."
  type = map(map(object({
    principal  = string
    privileges = list(string)
  })))
  default = {}
}

# ==========================================================
# Compute Configuration — Interactive Clusters
# ==========================================================

variable "clusters" {
  description = <<-EOT
    Interactive development clusters to provision.
    Key = logical name used in the cluster display name: "{environment}-{key}".
    Add or remove entries to provision/deprovision clusters.

    Example:
      clusters = {
        "engineering" = { owner = "alice@company.com" }
        "ml"          = { owner = "bob@company.com", node_type = "Standard_E16_v3", policy_key = "ml_clusters" }
      }

    policy_key options: shared_interactive | ml_clusters | job_clusters | lakeflow_pipelines
  EOT
  type = map(object({
    owner                    = string
    node_type                = optional(string, "Standard_DS4_v2")
    min_workers              = optional(number, 1)
    max_workers              = optional(number, 4)
    spark_version            = optional(string, "auto:latest-lts")
    runtime_engine           = optional(string, "STANDARD")
    data_security_mode       = optional(string, "SINGLE_USER")
    policy_key               = optional(string, "shared_interactive")
    enable_spot              = optional(bool, true)
    auto_termination_minutes = optional(number, 30)
  }))
  default = {}
}

# ==========================================================
# Compute Configuration — SQL Warehouses
# ==========================================================

variable "sql_warehouses" {
  description = <<-EOT
    SQL Warehouses to provision. Key = logical name used in the warehouse display name: "{environment}-{key}".
    Use separate warehouses for different teams or workload types (engineering, analytics, bi).

    Example:
      sql_warehouses = {
        "shared"    = {}
        "analytics" = { size = "Medium", auto_stop_mins = 15 }
      }
  EOT
  type = map(object({
    size              = optional(string, "Small")
    type              = optional(string, "PRO")
    auto_stop_mins    = optional(number, 30)
    enable_serverless = optional(bool, true)
  }))
  default = {}
}

variable "enable_ml_autologging" {
  description = "Enable automatic MLflow experiment tracking across the workspace"
  type        = bool
  default     = false
}

variable "enforce_user_isolation" {
  description = "Enforce Unity Catalog user isolation (each user runs in their own container)"
  type        = bool
  default     = true
}

# ==========================================================
# CI/CD Configuration
# ==========================================================

variable "cicd_sp_application_id" {
  description = <<-EOT
    Azure AD Application (client) ID of the CI/CD Service Principal.
    When set, registers the SP in the Databricks account and grants workspace USER access —
    enabling DATABRICKS_AZURE_* authentication in GitHub Actions.
    Set to the same value as AZURE_CLIENT_ID in your GitHub repository variables.
    Leave null to skip SP registration (local development without CI/CD).
    See: docs/guides/cicd-setup.md
  EOT
  type        = string
  default     = null
}

# ==========================================================
# Local Development — Databricks Provider Auth
# ==========================================================
# The workspace provider uses azure_workspace_resource_id (Azure AD auth) in CI/CD.
# For local dev with a PAT profile, set databricks_workspace_url to avoid the
# "more than one authorization method" conflict.
# See providers.tf for the full explanation.

variable "databricks_workspace_url" {
  description = "Workspace URL override for local development (e.g. https://adb-xxxx.azuredatabricks.net). When set, disables azure_workspace_resource_id so PAT profiles work. Leave null in CI/CD."
  type        = string
  default     = null
}

# ==========================================================
# Workload Service Principal Configuration
# ==========================================================

variable "enable_workload_sp" {
  description = "Enable creation of a dedicated service principal for workload execution (jobs, pipelines). Recommended for production."
  type        = bool
  default     = false
}

variable "workload_sp_name" {
  description = "Display name for the workload service principal"
  type        = string
  default     = "Lakehouse Workloads"
}

variable "workload_sp_allow_cluster_create" {
  description = "Allow the workload SP to create clusters (typically false, use job clusters)"
  type        = bool
  default     = false
}

variable "workload_sp_enable_sql_access" {
  description = "Enable Databricks SQL access for the workload SP"
  type        = bool
  default     = true
}

variable "workload_sp_workspace_permission" {
  description = "Workspace-level permission for workload SP (null, USER, or ADMIN)"
  type        = string
  default     = null
  validation {
    condition     = var.workload_sp_workspace_permission == null || contains(["USER", "ADMIN"], var.workload_sp_workspace_permission)
    error_message = "workload_sp_workspace_permission must be null, USER, or ADMIN"
  }
}

variable "workload_sp_catalog_grants" {
  description = "Map of catalog name to list of privileges for the workload SP."
  type        = map(list(string))
  default     = {}
}

variable "workload_sp_schema_grants" {
  description = "Map of fully-qualified schema name to list of privileges for the workload SP."
  type        = map(list(string))
  default     = {}
}

variable "workload_sp_volume_grants" {
  description = "Map of fully-qualified volume name to list of privileges for the workload SP."
  type        = map(list(string))
  default     = {}
}

variable "store_workload_sp_in_keyvault" {
  description = "Store workload SP credentials in Azure Key Vault for secure access"
  type        = bool
  default     = true
}

variable "workload_sp_secret_expiration" {
  description = "Workload SP client secret expiration duration (e.g., '8760h' for 1 year, '4380h' for 6 months)"
  type        = string
  default     = "8760h"
}

# ==========================================================
# Tags
# ==========================================================

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    "Project"   = "LakehouseBlueprint"
    "ManagedBy" = "OpenTofu"
  }
}

# ==========================================================
# Project Metadata
# ==========================================================

variable "project_name" {
  description = "Project identifier added as a 'Project' tag to the resource group"
  type        = string
  default     = "LakehouseBlueprint"
}

variable "project_slug" {
  description = "Short slug (lowercase, [a-z0-9], <=10) that namespaces shared resource names so multiple blueprint instances can coexist in one subscription/tenant."
  type        = string
  default     = "lakehouse"
}

# ==========================================================
# Observability — Log Analytics
# ==========================================================

variable "log_analytics_sku" {
  description = "Log Analytics workspace pricing tier (PerGB2018 is the standard pay-as-you-go tier)"
  type        = string
  default     = "PerGB2018"
}

# ==========================================================
# Key Vault — Advanced Settings
# ==========================================================

variable "key_vault_rbac_propagation_wait" {
  description = "Duration to wait after Key Vault RBAC assignment before creating Databricks secret scope. Azure RBAC propagation typically takes 2-3 minutes. (e.g. '180s', '5m')"
  type        = string
  default     = "180s"
}

variable "key_vault_secret_scope_name" {
  description = "Name of the Databricks secret scope backed by Azure Key Vault"
  type        = string
  default     = "kv-backed-scope"
}

# ==========================================================
# Workspace Security Feature Flags
# ==========================================================

variable "enable_enhanced_security" {
  description = "Enable Enhanced Security Monitoring on the Databricks workspace (Premium tier only)"
  type        = bool
  default     = true
}

variable "enable_automatic_cluster_updates" {
  description = "Enable automatic cluster security/version updates on a maintenance schedule"
  type        = bool
  default     = true
}

# ==========================================================
# Governance Feature Flags
# ==========================================================

variable "enable_cluster_policies" {
  description = "Create Databricks cluster governance policies (shared_interactive, job_clusters, ml_clusters, lakeflow_pipelines)"
  type        = bool
  default     = true
}

variable "require_unity_catalog" {
  description = "Enforce Unity Catalog data security mode in all cluster policies"
  type        = bool
  default     = true
}

variable "require_serverless" {
  description = "Prefer serverless compute in governance policies"
  type        = bool
  default     = true
}

variable "enable_token_policy" {
  description = "Configure PAT token management policy (max lifetime, MFA enforcement)"
  type        = bool
  default     = true
}

# ==========================================================
# Unity Catalog Feature Flags
# ==========================================================

variable "enable_system_tables" {
  description = "Enable Unity Catalog system tables (audit, lineage, billing)"
  type        = bool
  default     = true
}

variable "enable_predictive_optimization" {
  description = "Enable Databricks predictive optimization for automatic Delta table maintenance"
  type        = bool
  default     = true
}

variable "enable_workspace_binding" {
  description = "Enable workspace-level catalog binding (ISOLATED mode enforcement)"
  type        = bool
  default     = true
}

# ==========================================================
# Governance — Policy Tuning
# ==========================================================

variable "interactive_max_clusters_per_user" {
  description = "Maximum number of interactive clusters a user can run simultaneously (set per environment: 5 for dev, 2 for prod)"
  type        = number
  default     = 5
}

variable "job_max_clusters_per_user" {
  description = "Maximum number of job clusters a user can run simultaneously"
  type        = number
  default     = 10
}

variable "ml_max_clusters_per_user" {
  description = "Maximum number of ML clusters a user can run simultaneously"
  type        = number
  default     = 3
}

variable "autotermination_min_floor" {
  description = "Minimum allowed autotermination (minutes) enforced across all cluster policies"
  type        = number
  default     = 10
}

variable "job_autotermination_minutes" {
  description = "Fixed autotermination time for job clusters (minutes)"
  type        = number
  default     = 15
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

variable "ml_spark_version" {
  description = "Default Databricks Runtime version for ML cluster policy (e.g. 'auto:latest-ml')"
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

variable "pipeline_max_workers" {
  description = "Maximum autoscale workers for Lakeflow/DLT pipeline clusters"
  type        = number
  default     = 10
}
