# ==========================================================
# Account Identity Management (AIM)
# ==========================================================
# Syncs Azure AD groups to Databricks without SCIM or Premium license.
# Groups are defined per environment in aim_groups (dev.tfvars / prod.tfvars).
# See: docs/guides/aim-setup.md

module "databricks_aim" {
  source = "./modules/databricks-aim"

  providers = {
    azuread              = azuread
    databricks.account   = databricks.account
    databricks.workspace = databricks.workspace
  }

  # When aim_group_ids are pre-provided (by create-azure-groups.sh via the wizard),
  # skip group creation — the CI/CD SP needs no Group.ReadWrite.All permission.
  # When aim_group_ids is empty (legacy / manual tofu run), fall back to creating
  # groups from aim_groups (requires Group.ReadWrite.All on the CI/CD SP).
  create_azure_groups = length(var.aim_group_ids) == 0
  aim_group_ids       = var.aim_group_ids
  groups              = var.aim_groups

  # Workspace assignments are constructed from aim_groups:
  # admins get ADMIN, all other roles get USER.
  workspace_assignments = {
    for key, group in var.aim_groups : "${key}_${var.environment}" => {
      workspace_id = module.databricks_workspace.databricks_workspace_id
      group_key    = key
      permissions  = [key == "admins" ? "ADMIN" : "USER"]
    }
  }

  tags = [var.environment, "databricks", "aim"]

  depends_on = [module.databricks_workspace]
}

# ==========================================================
# CI/CD Service Principal
# ==========================================================
# Registers the GitHub Actions SP in the Databricks account and grants
# workspace USER access — enabling DATABRICKS_AZURE_* authentication
# in GitHub Actions for bundle deployments without PAT tokens.
# Activated by setting cicd_sp_application_id in tfvars.

resource "databricks_service_principal" "cicd" {
  count    = var.cicd_sp_application_id != null ? 1 : 0
  provider = databricks.account

  application_id       = var.cicd_sp_application_id
  display_name         = "GitHub Actions CI/CD (${var.environment})"
  allow_cluster_create = true

  lifecycle {
    ignore_changes = [active]
  }

  depends_on = [module.databricks_workspace]
}

resource "databricks_mws_permission_assignment" "cicd_workspace_user" {
  count    = var.cicd_sp_application_id != null ? 1 : 0
  provider = databricks.account

  workspace_id = module.databricks_workspace.databricks_workspace_id
  principal_id = databricks_service_principal.cicd[0].id
  permissions  = ["ADMIN"] # Workspace admin required: SP needs metastore-admin rights to CREATE EXTERNAL LOCATION during tofu apply

  depends_on = [databricks_service_principal.cicd]
}

# ==========================================================
# Workload Service Principal (OPTIONAL)
# ==========================================================
# Creates a dedicated service principal for production workload execution
# (jobs, pipelines, workflows). Enable via enable_workload_sp = true in tfvars.

module "workload_sp" {
  count  = var.enable_workload_sp ? 1 : 0
  source = "./modules/databricks-workload-sp"

  providers = {
    databricks.account   = databricks.account
    databricks.workspace = databricks.workspace
  }

  service_principal_name = var.workload_sp_name
  environment            = var.environment
  bootstrap_mode         = var.bootstrap_mode

  databricks_workspace_id  = module.databricks_workspace.databricks_workspace_id
  allow_cluster_create     = var.workload_sp_allow_cluster_create
  enable_sql_access        = var.workload_sp_enable_sql_access
  workspace_permission     = var.workload_sp_workspace_permission

  catalog_grants = var.workload_sp_catalog_grants
  schema_grants  = var.workload_sp_schema_grants
  volume_grants  = var.workload_sp_volume_grants

  store_credentials_in_keyvault = var.store_workload_sp_in_keyvault
  key_vault_id                  = var.store_workload_sp_in_keyvault ? module.key_vault.key_vault_id : null
  secret_prefix                 = "workload-sp-${var.environment}"

  client_secret_expiration = var.workload_sp_secret_expiration

  tags = [var.environment, "databricks", "workload"]

  depends_on = [
    module.databricks_aim,
    module.unity_catalog,
    time_sleep.wait_for_rbac_propagation
  ]
}
