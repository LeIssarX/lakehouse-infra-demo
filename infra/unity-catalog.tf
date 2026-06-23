# ==========================================================
# Module: Unity Catalog
# ==========================================================

locals {
  # Aggregate all container URLs from all storage accounts into Unity Catalog external locations.
  # Key pattern: "{account_key}-{container}", e.g. "lake-raw", "secure-pii"
  # This ensures every container in every storage account is accessible from Unity Catalog.
  all_external_locations = merge([
    for sa_key, sa in module.storage : {
      for container, url in sa.container_urls :
      "${sa_key}-${container}" => url
    }
  ]...)

  # The "lake" account is the Unity Catalog Metastore root storage.
  # This must match the required "lake" key in var.storage_accounts.
  metastore_storage_url = module.storage["lake"].metastore_url
}

# ==========================================================
# Dev only: delete stale UC storage credential before unity_catalog runs
# ==========================================================
# On a greenfield re-run (workspace deleted + fresh state), the Databricks
# storage credential persists in the account-level metastore even though the
# Azure workspace is gone. This triggers in-apply cleanup AFTER the workspace
# is created (via triggers_replace) but BEFORE unity_catalog tries to create
# the credential — preventing the "already exists" error.
# Prod: count = 0, this resource is never created.

resource "terraform_data" "cleanup_stale_uc" {
  count = var.environment == "dev" ? 1 : 0

  # Trigger whenever the workspace is freshly provisioned (id changes or first apply).
  triggers_replace = [module.databricks_workspace.databricks_workspace_id]

  provisioner "local-exec" {
    # Pass the just-created workspace URL and catalog-derived credential name so
    # the script can skip the az-lookup branch (workspace definitely exists here).
    command = "bash \"${path.module}/../scripts/cleanup-databricks-account.sh\" \"${var.environment}\" \"${module.databricks_workspace.workspace_url}\" || true"
  }

  depends_on = [
    module.databricks_workspace,
    # Wait for workspace admin assignment so the CI/CD SP has workspace admin
    # rights before it tries to delete the credential. Without this, the cleanup
    # runs concurrently with databricks_mws_permission_assignment and gets 403.
    module.databricks_aim,
    # Also wait for the CI/CD SP's own ADMIN assignment — the cleanup script
    # uses the SP's client credentials token and needs it to be a workspace ADMIN
    # (→ metastore admin) before it can see and delete stale external locations.
    databricks_mws_permission_assignment.cicd_workspace_user,
  ]
}

module "unity_catalog" {
  source = "./modules/unity-catalog"

  providers = {
    databricks = databricks.workspace
  }

  # Workspace IDs
  workspace_id            = module.databricks_workspace.workspace_id            # Azure Resource ID
  databricks_workspace_id = module.databricks_workspace.databricks_workspace_id # Numeric ID
  workspace_url           = module.databricks_workspace.workspace_url

  # Metastore Configuration
  # Mode is set per environment in tfvars:
  #   - 'auto'      Use workspace's auto-provisioned metastore (dev, new workspaces)
  #   - 'existing'  Attach to shared regional metastore (prod → reads from dev remote state)
  #   - 'create'    Create a new metastore (cross-region prod)
  use_workspace_metastore = var.unity_catalog_metastore_mode == "auto"
  create_metastore        = var.unity_catalog_metastore_mode == "create"

  # Prod: attach workspace to the shared dev metastore (retrieved from remote state).
  # Dev: both locals.dev_metastore_id and var.unity_catalog_metastore_id are null.
  assign_metastore_to_workspace = var.unity_catalog_metastore_mode == "existing" || var.unity_catalog_metastore_mode == "create"
  metastore_id                  = var.unity_catalog_metastore_mode == "existing" ? coalesce(local.dev_metastore_id, var.unity_catalog_metastore_id) : null
  metastore_name                = var.unity_catalog_metastore_mode == "create" ? var.unity_catalog_metastore_name : null
  storage_root                  = var.unity_catalog_metastore_mode == "create" ? local.metastore_storage_url : null
  region                        = var.unity_catalog_metastore_mode == "create" ? var.location : null

  # Storage credential
  access_connector_id = module.databricks_workspace.access_connector_id

  # Catalog
  catalog_name           = var.catalog_name
  catalog_isolation_mode = var.catalog_isolation_mode
  catalog_storage_root   = local.metastore_storage_url

  # External locations (all containers from all storage accounts)
  external_locations = local.all_external_locations

  # CI/CD SP — grants ALL_PRIVILEGES on storage credential and all external locations
  # so tofu plan can refresh their state without "cannot read external location" errors.
  cicd_sp_application_id = var.cicd_sp_application_id

  # Schemas
  schemas = var.catalog_schemas

  # Modern features
  enable_system_tables           = var.enable_system_tables
  enable_predictive_optimization = var.enable_predictive_optimization
  enable_workspace_binding       = var.enable_workspace_binding

  tags = var.tags

  depends_on = [
    module.databricks_workspace,
    module.storage,
    terraform_data.cleanup_stale_uc,
    # CI/CD SP must have workspace ADMIN before the UC module tries to create the
    # storage credential and external locations — the SP is the Terraform identity
    # running the apply and needs CREATE EXTERNAL LOCATION permission which is
    # inherited from workspace admin → metastore admin.
    databricks_mws_permission_assignment.cicd_workspace_user,
  ]
}

# ==========================================================
# Module: Databricks Grants
# ==========================================================
# Manages Unity Catalog permissions independently from catalog provisioning.

module "databricks_grants" {
  source = "./modules/databricks-grants"

  providers = {
    databricks = databricks.workspace
  }

  catalog_name         = var.catalog_name
  catalog_grants       = var.catalog_grants
  schema_grants        = var.schema_grants
  system_schema_grants = var.system_schema_grants

  depends_on = [module.unity_catalog]
}
