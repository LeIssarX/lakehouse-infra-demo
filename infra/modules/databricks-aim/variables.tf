# ==========================================================
# Input Variables - Databricks AIM Module
# ==========================================================

variable "create_azure_groups" {
  description = "Whether to create Azure AD groups or use existing ones (requires Group.ReadWrite.All permission when true)"
  type        = bool
  default     = false # Default to false for safer deployments without elevated permissions
}

variable "groups" {
  description = "Azure AD security groups to create and sync to Databricks"
  type = map(object({
    display_name               = string
    description                = string
    mail_nickname              = string
    allow_cluster_create       = optional(bool, false)
    allow_instance_pool_create = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.groups : can(regex("^[a-zA-Z0-9-]+$", v.mail_nickname))])
    error_message = "Mail nickname must contain only alphanumeric characters and hyphens."
  }
}

variable "workspace_assignments" {
  description = "Assign groups to specific workspaces with permissions"
  type = map(object({
    workspace_id = string
    group_key    = string
    permissions  = list(string) # ["USER", "ADMIN"]
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.workspace_assignments : contains(["USER", "ADMIN"], v.permissions[0])])
    error_message = "Permissions must be one of: USER, ADMIN."
  }
}

variable "direct_users" {
  description = "Individual user accounts to create (use groups when possible)"
  type = map(object({
    user_principal_name = string
    display_name        = string
    object_id           = string
  }))
  default = {}
}

variable "workspace_group_assignments" {
  description = "Assign account groups to workspace-level groups"
  type = map(object({
    workspace_id = string
    groups = map(object({
      workspace_group    = string
      workspace_group_id = string
    }))
  }))
  default = {}
}

variable "aim_group_ids" {
  description = "Pre-created Azure AD group object IDs (key → object_id). When non-empty, Terraform uses these directly and skips all Azure AD provider calls — no Group.ReadWrite.All permission required for the CI/CD service principal. Run scripts/create-azure-groups.sh to populate."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to Azure resources"
  type        = list(string)
  default     = []
}
