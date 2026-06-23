# ==========================================================
# Databricks Workload Service Principal - Variables
# ==========================================================

# ==========================================================
# Required Variables
# ==========================================================

variable "service_principal_name" {
  description = "Display name for the service principal (e.g., 'Lakehouse Pipeline (prod)')"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
}

variable "bootstrap_mode" {
  description = "Bootstrap mode: Skip RBAC-dependent validations during first deployment. Set to true for greenfield deployments."
  type        = bool
  default     = false
}

# ==========================================================
# Databricks Configuration
# ==========================================================

variable "databricks_workspace_id" {
  description = "Databricks workspace ID for permission assignments"
  type        = string
  default     = null
}

variable "allow_cluster_create" {
  description = "Allow the service principal to create clusters"
  type        = bool
  default     = false # Least privilege: most workloads use job clusters
}

variable "allow_instance_pool_create" {
  description = "Allow the service principal to create instance pools"
  type        = bool
  default     = false
}

variable "enable_sql_access" {
  description = "Enable Databricks SQL access for the service principal"
  type        = bool
  default     = true
}

variable "workspace_permission" {
  description = "Workspace-level permission (USER, ADMIN). Set to null for no workspace-level permission."
  type        = string
  default     = null # Most workload SPs don't need workspace permissions

  validation {
    condition     = var.workspace_permission == null || contains(["USER", "ADMIN"], var.workspace_permission)
    error_message = "workspace_permission must be null, USER, or ADMIN"
  }
}

# ==========================================================
# Unity Catalog Grants
# ==========================================================

variable "catalog_grants" {
  description = "Map of catalog name to list of privileges (e.g., {\"lakehouse_prod\" = [\"USE CATALOG\", \"USE SCHEMA\", \"SELECT\"]})"
  type        = map(list(string))
  default     = {}
}

variable "schema_grants" {
  description = "Map of schema name to list of privileges (e.g., {\"lakehouse_prod.silver\" = [\"USE SCHEMA\", \"MODIFY\"]})"
  type        = map(list(string))
  default     = {}
}

variable "volume_grants" {
  description = "Map of volume name to list of privileges (e.g., {\"lakehouse_prod.bronze.landing\" = [\"READ VOLUME\", \"WRITE VOLUME\"]})"
  type        = map(list(string))
  default     = {}
}

# ==========================================================
# Azure AD Configuration
# ==========================================================

variable "owners" {
  description = "List of Azure AD object IDs that will be owners of the application/service principal"
  type        = list(string)
  default     = []
}

variable "create_client_secret" {
  description = "Create a client secret for the service principal"
  type        = bool
  default     = true
}

variable "client_secret_expiration" {
  description = "Client secret expiration duration (e.g., '8760h' for 1 year, '17520h' for 2 years)"
  type        = string
  default     = "8760h" # 1 year
}

# ==========================================================
# Key Vault Integration (Optional)
# ==========================================================

variable "store_credentials_in_keyvault" {
  description = "Store the client ID and secret in Azure Key Vault"
  type        = bool
  default     = false
}

variable "key_vault_id" {
  description = "Azure Key Vault ID for storing credentials (required if store_credentials_in_keyvault = true)"
  type        = string
  default     = null
}

variable "secret_prefix" {
  description = "Prefix for Key Vault secret names (e.g., 'workload-sp')"
  type        = string
  default     = "workload-sp"
}

# ==========================================================
# Tags
# ==========================================================

variable "tags" {
  description = "Additional tags to apply to Azure resources"
  type        = list(string)
  default     = []
}
