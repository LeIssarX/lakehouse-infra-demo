# ==========================================================
# Unity Catalog Module
# ==========================================================

# Note: This module requires Databricks provider to be configured
# with account-level or workspace-level authentication

# ==========================================================
# Metastore (Account-Level Resource)
# ==========================================================

# Option 1: Create new metastore (legacy/manual setup)
resource "databricks_metastore" "this" {
  count = var.create_metastore ? 1 : 0

  name          = var.metastore_name
  storage_root  = var.storage_root
  region        = var.region
  force_destroy = false # Prevent accidental deletion

  # Optional: Enable Delta Sharing for external data sharing
  # delta_sharing_scope               = "INTERNAL_AND_EXTERNAL"
  # delta_sharing_recipient_token_lifetime_in_seconds = 86400

  # Optional: Set explicit owner (defaults to creator)
  # owner = var.owner_principal
}

# Option 2: Use existing metastore by ID
#  Note: Data source deactivated - we use the ID directly to avoid account provider requirement
# data "databricks_metastore" "existing" {
#   count = !var.create_metastore && !var.use_workspace_metastore && var.metastore_id != null ? 1 : 0
#   metastore_id = var.metastore_id
# }

# Option 3: Auto-discover workspace's metastore (for Auto-UC workspaces deployed after Nov 2023)
data "databricks_current_metastore" "auto" {
  count = var.use_workspace_metastore ? 1 : 0
}

locals {
  # Safe metastore_id extraction with fallback for empty metastore_info
  auto_metastore_id = (
    var.use_workspace_metastore && length(data.databricks_current_metastore.auto) > 0
    ? try(data.databricks_current_metastore.auto[0].metastore_info[0].metastore_id, null)
    : null
  )

  metastore_id = (
    var.create_metastore ? databricks_metastore.this[0].id :
    var.use_workspace_metastore ? local.auto_metastore_id :
    var.metastore_id # Use the ID directly, no data source needed
  )
}

# ==========================================================
# Metastore Assignment (Assign to Workspace)
# ==========================================================
# Note: Skip assignment for Auto-UC workspaces (already assigned)

resource "databricks_metastore_assignment" "this" {
  count = var.assign_metastore_to_workspace ? 1 : 0

  metastore_id = local.metastore_id
  workspace_id = var.databricks_workspace_id # Numeric workspace ID (not Azure Resource ID)
}

# ==========================================================
# Storage Credential (Managed Identity)
# ==========================================================

resource "databricks_storage_credential" "external" {
  name           = "${var.catalog_name}_credential"
  isolation_mode = var.catalog_isolation_mode
  comment        = "Storage credential for ${var.catalog_name} using Azure Managed Identity"
  force_update   = true # Allow updates even with dependent resources

  azure_managed_identity {
    access_connector_id = var.access_connector_id
  }

  # Optional: Set explicit owner (defaults to creator)
  # owner = var.owner_principal

  lifecycle {
    # isolation_mode may already be set correctly on existing credentials;
    # ignore drift to avoid requiring MANAGE privilege when already configured.
    ignore_changes = [isolation_mode]
  }
}

# ==========================================================
# Workspace Binding for Storage Credential (ISOLATED mode)
# ==========================================================

resource "databricks_workspace_binding" "credential" {
  count = var.enable_workspace_binding && var.catalog_isolation_mode == "ISOLATED" ? 1 : 0

  securable_name = databricks_storage_credential.external.name
  securable_type = "storage_credential"
  workspace_id   = var.databricks_workspace_id

  depends_on = [databricks_storage_credential.external]
}

# ==========================================================
# External Locations (ADLS Gen2 Containers)
# ==========================================================

resource "databricks_external_location" "locations" {
  for_each = var.external_locations

  # Derive a stable Databricks name from the container part of the map key.
  # Map keys follow the pattern "{account}-{container}" (e.g. "lake-core").
  # Using only the container name keeps the Databricks resource name unchanged
  # when storage account keys are refactored, preventing forced replacements.
  name            = "${var.catalog_name}_${join("-", slice(split("-", each.key), 1, length(split("-", each.key))))}"
  url             = each.value
  credential_name = databricks_storage_credential.external.name
  isolation_mode  = var.catalog_isolation_mode
  comment         = "External location for ${join("-", slice(split("-", each.key), 1, length(split("-", each.key))))} layer - Managed by Terraform"

  # Optional: Set explicit owner (defaults to creator)
  # owner = var.owner_principal

  lifecycle {
    # isolation_mode may already be configured on existing locations;
    # ignore drift to avoid MANAGE-privilege errors on CI/CD-owned resources.
    ignore_changes = [isolation_mode]
  }

  depends_on = [
    databricks_storage_credential.external,
    databricks_workspace_binding.credential,
  ]
}

# ==========================================================
# Workspace Binding for External Locations (ISOLATED mode)
# ==========================================================

resource "databricks_workspace_binding" "locations" {
  for_each = var.enable_workspace_binding && var.catalog_isolation_mode == "ISOLATED" ? var.external_locations : {}

  securable_name = databricks_external_location.locations[each.key].name
  securable_type = "external_location"
  workspace_id   = var.databricks_workspace_id

  depends_on = [databricks_external_location.locations]
}

# ==========================================================
# CI/CD SP Grants (Storage Credential + External Locations)
# ==========================================================
# The CI/CD SP must be able to read external locations during tofu plan (refresh).
# Without ALL_PRIVILEGES on these resources, plan fails with "cannot read external location".
# These grants are co-located with resource creation so the owner (creator) applies them.

resource "databricks_grants" "cicd_storage_credential" {
  count              = var.cicd_sp_application_id != null ? 1 : 0
  storage_credential = databricks_storage_credential.external.id

  grant {
    principal  = var.cicd_sp_application_id
    privileges = ["ALL_PRIVILEGES", "MANAGE"]
  }

  depends_on = [databricks_storage_credential.external]
}

resource "databricks_grants" "cicd_external_locations" {
  for_each          = var.cicd_sp_application_id != null ? var.external_locations : {}
  external_location = databricks_external_location.locations[each.key].id

  grant {
    principal  = var.cicd_sp_application_id
    privileges = ["ALL_PRIVILEGES", "MANAGE"]
  }

  depends_on = [databricks_external_location.locations]
}

# ==========================================================
# Catalog
# ==========================================================

resource "databricks_catalog" "this" {
  name           = var.catalog_name
  isolation_mode = var.catalog_isolation_mode
  comment        = "Unity Catalog for data lakehouse - Managed by Terraform"

  # For Auto-UC workspaces with Default Storage:
  # Specify catalog-level managed storage location
  storage_root = var.catalog_storage_root

  properties = merge(
    var.tags,
    {
      "managed_by" = "opentofu"
    }
  )

  # Optional: Set explicit owner (defaults to creator)
  # owner = var.owner_principal

  depends_on = [
    databricks_external_location.locations,
    databricks_workspace_binding.locations
  ]
}

# ==========================================================
# Workspace Binding for Catalog (ISOLATED mode)
# ==========================================================

resource "databricks_workspace_binding" "catalog" {
  count = var.enable_workspace_binding && var.catalog_isolation_mode == "ISOLATED" ? 1 : 0

  securable_name = databricks_catalog.this.name
  securable_type = "catalog"
  workspace_id   = var.databricks_workspace_id

  depends_on = [databricks_catalog.this]
}

# ==========================================================
# Schemas (Data Layers)
# ==========================================================

resource "databricks_schema" "schemas" {
  for_each = var.schemas

  catalog_name = databricks_catalog.this.name
  name         = each.key
  comment      = each.value.comment
  # Use catalog's Default Storage (no explicit storage_root for managed schemas)
  # External tables will reference external_locations directly
  force_destroy = false

  properties = merge(
    var.tags,
    {
      "managed_by" = "opentofu"
      "layer"      = each.key
    }
  )

  # Optional: Set explicit owner (defaults to creator)
  # owner = var.owner_principal

  depends_on = [
    databricks_catalog.this,
    databricks_workspace_binding.catalog
  ]
}

# ==========================================================
# Volumes (for unstructured data)
# ==========================================================

locals {
  # Flatten volumes from all schemas
  volumes = flatten([
    for schema_name, schema_config in var.schemas : [
      for volume_name, volume_config in schema_config.volumes : {
        key         = "${schema_name}_${volume_name}"
        schema_name = schema_name
        volume_name = volume_name
        type        = volume_config.type
        comment     = volume_config.comment
        path        = volume_config.path
      }
    ]
  ])
}

resource "databricks_volume" "volumes" {
  for_each = { for v in local.volumes : v.key => v }

  catalog_name = databricks_catalog.this.name
  schema_name  = databricks_schema.schemas[each.value.schema_name].name
  name         = each.value.volume_name
  volume_type  = each.value.type
  comment      = each.value.comment

  # For EXTERNAL volumes, specify storage path
  storage_location = each.value.type == "EXTERNAL" ? each.value.path : null

  # Optional: Set explicit owner (defaults to creator)
  # owner = var.owner_principal

  depends_on = [databricks_schema.schemas]
}

# ==========================================================
# Grants (Permissions)
# ==========================================================

# Catalog-level grants
resource "databricks_grants" "catalog" {
  count = length(var.catalog_grants) > 0 ? 1 : 0

  catalog = databricks_catalog.this.name

  dynamic "grant" {
    for_each = var.catalog_grants
    content {
      principal  = grant.value.principal
      privileges = grant.value.privileges
    }
  }

  depends_on = [databricks_catalog.this]
}

# Schema-level grants
resource "databricks_grants" "schemas" {
  for_each = var.schema_grants

  schema = "${databricks_catalog.this.name}.${each.key}"

  dynamic "grant" {
    for_each = each.value
    content {
      principal  = grant.value.principal
      privileges = grant.value.privileges
    }
  }

  depends_on = [databricks_schema.schemas]
}

# ==========================================================
# System Tables Configuration
# ==========================================================

# System schemas (access, billing, query, lineage) are auto-provisioned by
# Unity Catalog and do not need explicit OpenTofu management. The Databricks
# provider has a known bug with databricks_system_schema that produces
# "inconsistent result after apply" errors. Since these schemas exist
# automatically, managing them here provides no benefit.
#
# If you previously had enable_system_tables = true, the removed block below
# removes the state entries without destroying the schemas in Databricks.

removed {
  from = databricks_system_schema.enabled

  lifecycle {
    destroy = false
  }
}

# ==========================================================
# Notes for Modern Features
# ==========================================================

# LAKEFLOW PIPELINES:
# Use schemas created above as targets/sources for Lakeflow pipelines
# Bronze -> Lakeflow Connect ingestion
# Silver -> Lakeflow cleansing/transformation
# Gold -> Lakeflow aggregation/analytics

# PREDICTIVE OPTIMIZATION:
# Enable on individual tables after creation:
# ALTER TABLE catalog.schema.table 
# SET TBLPROPERTIES ('delta.enablePredictiveOptimization' = 'true');

# DELTA SHARING:
# Create shares and recipients:
# resource "databricks_share" "analytics" {
#   name = "${var.catalog_name}_share"
#   # Add tables to share
# }
