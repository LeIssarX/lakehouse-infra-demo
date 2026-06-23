# ==========================================================
# Required Variables
# ==========================================================

variable "application_name" {
  description = "Display name for the Azure AD SCIM application"
  type        = string
  default     = "Databricks SCIM Provisioning"
}

variable "databricks_account_id" {
  description = "Databricks Account ID (required for SCIM tenant URL)"
  type        = string
}

# ==========================================================
# Optional Variables
# ==========================================================

variable "assigned_groups" {
  description = "Map of Azure AD groups to assign to SCIM app (key = group name, value = {object_id, display_name})"
  type = map(object({
    object_id    = string
    display_name = string
  }))
  default = {}
}

variable "assigned_users" {
  description = "Map of Azure AD users to assign to SCIM app (key = user principal name, value = {object_id, display_name})"
  type = map(object({
    object_id    = string
    display_name = string
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to Azure AD resources"
  type        = list(string)
  default     = ["databricks", "scim", "provisioning"]
}
