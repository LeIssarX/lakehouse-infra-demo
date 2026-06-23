# Infrastructure

OpenTofu root module for the Azure Data Lakehouse platform.
Manages network, storage, identity, governance, and Databricks workspace resources.

## Directory Structure

```text
infra/
├── main.tf               # Module wiring — calls all modules with wired outputs
├── providers.tf          # AzureRM, AzureAD, Databricks provider configuration
├── variables.tf          # All input variables (≈ 75 variables, documented below)
├── outputs.tf            # Root module outputs (workspace URL, storage, catalog IDs…)
├── resource-group.tf     # Azure Resource Group
├── network.tf            # VNet, subnets, NSGs, UDRs (optional — VNet injection)
├── storage.tf            # ADLS Gen2 storage account + containers
├── workspace.tf          # Databricks workspace + Access Connector
├── key-vault.tf          # Azure Key Vault + Databricks secret scope
├── unity-catalog.tf      # Unity Catalog metastore, catalog, schemas, volumes
├── governance.tf         # Cluster policies, token policies, IP allowlists
├── identity.tf           # AIM groups + SCIM (optional), CI/CD SP, workload SP
├── compute.tf            # Dev interactive cluster, SQL warehouse
│
├── common.tfvars.example # Template for global values (copy → common.tfvars)
│
├── envs/
│   ├── dev/
│   │   ├── backend.hcl.example  # Template for dev backend config
│   │   ├── dev.tfvars.example   # Template for dev variable overrides
│   │   └── README.md
│   └── prod/
│       ├── backend.hcl.example  # Template for prod backend config
│       ├── prod.tfvars.example  # Template for prod variable overrides
│       └── README.md
│
└── modules/
    ├── databricks-aim/          # Azure AD group → Databricks sync (recommended)
    ├── databricks-scim/         # Legacy SCIM (optional, requires account ID)
    ├── databricks-workspace/    # Workspace + Access Connector
    ├── databricks-compute/      # Dev clusters + SQL warehouses
    ├── databricks-governance/   # Cluster policies, token policies
    ├── databricks-grants/       # Unity Catalog permission management
    ├── databricks-workload-sp/  # Workload service principal automation
    ├── key-vault/               # Azure Key Vault + secret scopes
    ├── network/                 # VNet, subnets, NSGs, UDRs
    ├── storage/                 # ADLS Gen2 + containers + lifecycle
    └── unity-catalog/           # Metastore, catalogs, schemas, volumes
```

## Quick Start

```bash
# 1. Edit existing tfvars files with your values
# Edit infra/common.tfvars and infra/envs/dev/dev.tfvars

# 2. Create Azure storage backend (once per environment)
./scripts/create-backend.sh dev

# 3. Deploy using the wrapper script (recommended)
./scripts/tofu-wrapper.sh dev init
./scripts/tofu-wrapper.sh dev plan
./scripts/tofu-wrapper.sh dev apply

# 4. Or run OpenTofu directly from infra/
cd infra
tofu init -backend-config=envs/dev/backend.hcl -reconfigure
tofu plan  -var-file=common.tfvars -var-file=envs/dev/dev.tfvars
tofu apply -var-file=common.tfvars -var-file=envs/dev/dev.tfvars
```

Variable files load order (both are always required):

1. `infra/common.tfvars` — global values shared across environments
2. `infra/envs/{env}/{env}.tfvars` — environment-specific overrides

---

## Variable Reference

> **Required** variables have no default and must be provided in your `.tfvars` files.
> **Optional** variables have defaults that work out-of-the-box; override them as needed.

### Environment Configuration

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `environment` | `string` | — | ✅ | Environment name (`dev` or `prod`) |
| `bootstrap_mode` | `bool` | `false` | | Set `true` for first-ever deploy (greenfield) to skip RBAC-dependent data sources |

### Azure Configuration

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `subscription_id` | `string` | — | ✅ | Azure Subscription ID |
| `location` | `string` | `"westeurope"` | | Azure region for all resources |
| `resource_group_name` | `string` | — | ✅ | Name of the Resource Group to create |

### Databricks Configuration

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `databricks_account_id` | `string` | `null` | | Databricks Account ID. Required for AIM/SCIM. Find at accounts.azuredatabricks.net → Settings |
| `databricks_workspace_name` | `string` | — | ✅ | Name of the Databricks workspace |

### Workspace Configuration

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `workspace_sku` | `string` | `"premium"` | | Databricks SKU (`premium` or `trial`) |
| `enable_unity_catalog` | `bool` | `true` | | Enable Unity Catalog on the workspace |
| `enable_serverless_compute` | `bool` | `true` | | Enable serverless compute capability |
| `enable_enhanced_security` | `bool` | `true` | | Enable Enhanced Security Monitoring (Premium only) |
| `enable_automatic_cluster_updates` | `bool` | `true` | | Enable automatic cluster security/version updates |

### Observability

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `log_retention_days` | `number` | `30` | | Log Analytics retention in days (30 = dev, 90 = prod compliance) |
| `log_analytics_sku` | `string` | `"PerGB2018"` | | Log Analytics pricing tier |

### Unity Catalog

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `catalog_name` | `string` | — | ✅ | Unity Catalog catalog name (e.g. `lakehouse_dev`) |
| `catalog_isolation_mode` | `string` | `"ISOLATED"` | | `ISOLATED` (default — workspace sees only its catalog) or `OPEN` |
| `unity_catalog_metastore_mode` | `string` | `"auto"` | | `auto` (workspace metastore), `create` (new metastore), `existing` (use by ID) |
| `unity_catalog_metastore_id` | `string` | `null` | | Existing metastore ID (for `existing` mode; prod reads this from dev remote state) |
| `unity_catalog_metastore_name` | `string` | `null` | | New metastore name (required when `metastore_mode = "create"`) |
| `enable_system_tables` | `bool` | `true` | | Enable UC system tables (audit, lineage, billing) |
| `enable_predictive_optimization` | `bool` | `true` | | Enable automatic Delta table maintenance |
| `enable_workspace_binding` | `bool` | `true` | | Enforce ISOLATED mode workspace-catalog binding |
| `catalog_schemas` | `map(object)` | `{}` | | Schemas to create inside the catalog. Each key is the schema name. Supports `comment` and nested `volumes`. |

**`catalog_schemas` object shape:**

```hcl
catalog_schemas = {
  bronze = { comment = "Raw ingestion layer" }
  silver = { comment = "Curated layer" }
  gold   = {
    comment = "Aggregated layer"
    volumes = {
      exports = { type = "EXTERNAL", comment = "Export landing zone" }
    }
  }
}
```

### Remote State: Dev (prod only)

Used by prod to read the shared regional metastore ID from dev's OpenTofu state.
Leave all `dev_remote_state_*` variables unset in `dev.tfvars`.

| Variable | Type | Default | Description |
|---|---|---|---|
| `dev_remote_state_resource_group` | `string` | `null` | Resource group of dev state storage account |
| `dev_remote_state_storage_account` | `string` | `null` | Storage account name for dev remote state |
| `dev_remote_state_container` | `string` | `"tfstate"` | Container name for dev state |
| `dev_remote_state_key` | `string` | `"dev.terraform.tfstate"` | Blob key for dev state file |

### Network

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `enable_vnet_injection` | `bool` | `false` | | Deploy Databricks with a custom VNet |
| `vnet_name` | `string` | `null` | | VNet name (required when `enable_vnet_injection = true`) |
| `vnet_address_space` | `list(string)` | `["10.0.0.0/16"]` | | VNet address space |
| `public_subnet_address_prefixes` | `list(string)` | `["10.0.1.0/24"]` | | Public Databricks subnet CIDR |
| `private_subnet_address_prefixes` | `list(string)` | `["10.0.2.0/24"]` | | Private Databricks subnet CIDR |
| `enable_public_access` | `bool` | `true` | | Allow public network access (disable in prod with Private Link) |

### Storage

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `storage_account_prefix` | `string` | — | ✅ | Storage account name prefix (max 18 chars, lowercase alphanumeric) |
| `storage_account_tier` | `string` | `"Standard"` | | `Standard` or `Premium` |
| `storage_replication_type` | `string` | `"LRS"` | | `LRS`, `ZRS`, or `GRS` |
| `storage_containers` | `list(string)` | `["metastore","landing","raw","curated","core","mart","reporting","sharing"]` | | Containers to create (7-layer architecture) |
| `enable_storage_soft_delete` | `bool` | `true` | | Enable blob soft-delete |
| `storage_soft_delete_retention_days` | `number` | `7` | | Soft-delete retention window in days |
| `enable_private_endpoint` | `bool` | `false` | | Enable private endpoint for storage (requires VNet injection) |
| `enable_lifecycle_policy` | `bool` | `false` | | Enable automated Hot → Cool → Archive tiering |
| `lifecycle_containers` | `list(string)` | `["raw"]` | | Containers targeted by the lifecycle policy |
| `cool_after_days` | `number` | `30` | | Days before tiering to Cool |
| `archive_after_days` | `number` | `90` | | Days before tiering to Archive |
| `delete_after_days` | `number` | `365` | | Days before deletion (0 to disable) |

### Key Vault

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `key_vault_name` | `string` | `null` | | Key Vault name (auto-generated if omitted) |
| `enable_purge_protection` | `bool` | `false` | | Prevent permanent deletion — **required in prod** |
| `key_vault_soft_delete_retention_days` | `number` | `7` | | Soft-delete retention days (min 7, max 90) |
| `key_vault_allowed_ips` | `list(string)` | `[]` | | IP ranges allowed to access the Key Vault (CIDR) |
| `key_vault_rbac_propagation_wait` | `string` | `"180s"` | | Wait time for Azure RBAC propagation before creating secret scope |
| `key_vault_secret_scope_name` | `string` | `"kv-backed-scope"` | | Name of the Databricks secret scope backed by Key Vault |

### Governance

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `enable_cluster_policies` | `bool` | `true` | | Create cluster governance policies |
| `require_unity_catalog` | `bool` | `true` | | Enforce UC security mode in all cluster policies |
| `require_serverless` | `bool` | `true` | | Prefer serverless compute in policies |
| `enable_token_policy` | `bool` | `true` | | Configure PAT token management policy |
| `auto_termination_minutes` | `number` | `30` | | Auto-terminate idle clusters after N minutes |
| `max_cluster_lifetime_minutes` | `number` | `null` | | Max cluster lifetime in minutes (null = unlimited) |
| `max_workers_limit` | `number` | `10` | | Maximum workers per cluster |
| `enable_spot_instances` | `bool` | `true` | | Allow spot/preemptible instances |
| `max_token_lifetime_days` | `number` | `90` | | Maximum PAT token lifetime in days |
| `allowed_node_types` | `list(string)` | `["Standard_DS3_v2","Standard_DS4_v2","Standard_E8_v3"]` | | Allowed Azure VM types |
| `enable_ip_access_lists` | `bool` | `false` | | Enable IP allowlisting for workspace access |
| `governance_allowed_ips` | `list(string)` | `[]` | | Allowed IP ranges for workspace access (CIDR) |
| `interactive_max_clusters_per_user` | `number` | `5` | | Max interactive clusters per user (use 2 in prod) |
| `job_max_clusters_per_user` | `number` | `10` | | Max job clusters per user |
| `ml_max_clusters_per_user` | `number` | `3` | | Max ML clusters per user |

### Identity: AIM Groups

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `aim_groups` | `map(object)` | `{}` | | Azure AD groups to create and sync to Databricks via AIM |

**`aim_groups` object shape:**

```hcl
aim_groups = {
  admins = {
    display_name               = "Databricks-Admins-Dev"
    description                = "Dev workspace administrators"
    mail_nickname              = "Databricks-Admins-Dev"
    allow_cluster_create       = true     # optional, default false
    allow_instance_pool_create = false    # optional, default false
  }
}
```

See [`docs/guides/aim-setup.md`](../docs/guides/aim-setup.md) for the full recommended group configuration per environment.

### Unity Catalog Grants

| Variable | Type | Default | Description |
|---|---|---|---|
| `catalog_grants` | `map(object)` | `{}` | Catalog-level grants. Key = arbitrary label, value = `{ principal, privileges }` |
| `schema_grants` | `map(map(object))` | `{}` | Schema-level grants. Outer key = schema name, inner key = label |
| `system_schema_grants` | `map(map(object))` | `{}` | Grants on UC system schemas (e.g. `system.access`, `system.billing`) |

**Example:**

```hcl
catalog_grants = {
  engineers_use = {
    principal  = "Databricks-Engineers-Dev"
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
  }
}

schema_grants = {
  bronze = {
    engineers_write = {
      principal  = "Databricks-Engineers-Dev"
      privileges = ["USE_SCHEMA", "MODIFY", "SELECT", "CREATE_TABLE"]
    }
  }
}
```

### Compute

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `dev_cluster_owner` | `string` | `null` | | Email of the dev cluster single-user owner. Set to provision a cluster. |
| `dev_cluster_node_type` | `string` | `"Standard_DS4_v2"` | | Azure VM node type for the dev cluster |
| `dev_cluster_min_workers` | `number` | `1` | | Minimum autoscale workers |
| `dev_cluster_max_workers` | `number` | `4` | | Maximum autoscale workers |
| `spark_version` | `string` | `"auto:latest-lts"` | | Databricks Runtime version (e.g. `"15.4.x-scala2.12"`) |
| `data_security_mode` | `string` | `"SINGLE_USER"` | | UC security mode: `SINGLE_USER` or `USER_ISOLATION` |
| `enforce_user_isolation` | `bool` | `true` | | Enforce per-user containers via Unity Catalog |
| `enable_sql_warehouse` | `bool` | `false` | | Create a SQL warehouse |
| `sql_warehouse_size` | `string` | `"Small"` | | Warehouse size: `X-Small`, `Small`, `Medium`, `Large` |
| `sql_warehouse_type` | `string` | `"PRO"` | | `PRO` (supports AI/BI + serverless) or `CLASSIC` |
| `enable_serverless_sql` | `bool` | `true` | | Enable serverless compute for SQL warehouse |
| `sql_warehouse_auto_stop_mins` | `number` | `30` | | Idle stop time in minutes (0 = never stop) |
| `enable_ml_autologging` | `bool` | `false` | | Enable automatic MLflow experiment tracking workspace-wide |

### CI/CD Configuration

| Variable | Type | Default | Description |
|---|---|---|---|
| `cicd_sp_application_id` | `string` | `null` | Azure AD Application ID of the CI/CD SP. When set, registers it in Databricks with USER access. Match to `AZURE_CLIENT_ID` in GitHub variables. See [`docs/guides/cicd-setup.md`](../docs/guides/cicd-setup.md) |

### Workload Service Principal

| Variable | Type | Default | Description |
|---|---|---|---|
| `enable_workload_sp` | `bool` | `false` | Create a dedicated Azure AD SP for job/pipeline execution |
| `workload_sp_name` | `string` | `"Lakehouse Workloads"` | Display name for the workload SP |
| `workload_sp_allow_cluster_create` | `bool` | `false` | Allow the SP to create clusters (use job clusters instead) |
| `workload_sp_enable_sql_access` | `bool` | `true` | Grant Databricks SQL access to the SP |
| `workload_sp_workspace_permission` | `string` | `null` | Workspace permission: `null`, `USER`, or `ADMIN` |
| `workload_sp_catalog_grants` | `map(list(string))` | `{}` | Catalog grants: `{ "lakehouse_dev" = ["USE_CATALOG", "USE_SCHEMA", "SELECT"] }` |
| `workload_sp_schema_grants` | `map(list(string))` | `{}` | Schema grants: `{ "lakehouse_dev.bronze" = ["MODIFY", "SELECT"] }` |
| `workload_sp_volume_grants` | `map(list(string))` | `{}` | Volume grants: `{ "lakehouse_dev.bronze.raw_files" = ["READ_VOLUME"] }` |
| `store_workload_sp_in_keyvault` | `bool` | `true` | Store SP credentials in Azure Key Vault |
| `workload_sp_secret_expiration` | `string` | `"8760h"` | SP secret expiration (e.g. `"8760h"` = 1 year, `"4380h"` = 6 months) |

### Tags & Metadata

| Variable | Type | Default | Description |
|---|---|---|---|
| `tags` | `map(string)` | `{ "Project" = "LakehouseBlueprint", "ManagedBy" = "OpenTofu" }` | Tags applied to all resources |
| `project_name` | `string` | `"LakehouseBlueprint"` | Project tag added to the resource group |

---

## Module Overview

| Module | Provisioned Resources |
|---|---|
| `network` | VNet, subnets, NSGs, route tables |
| `storage` | ADLS Gen2 account, containers, lifecycle rules |
| `databricks-workspace` | Databricks workspace, Access Connector, Log Analytics, diagnostics |
| `key-vault` | Key Vault, RBAC assignments, Databricks secret scope |
| `unity-catalog` | Metastore (or binding to existing), catalog, schemas, volumes, system schemas |
| `databricks-governance` | Cluster policies (shared_interactive, job_clusters, ml_clusters, lakeflow_pipelines), token policy, IP access lists |
| `databricks-aim` | Azure AD group creation, Databricks account-level group sync |
| `databricks-scim` | (Optional) SCIM integration via Databricks account connector |
| `databricks-grants` | Catalog, schema, and system schema privilege grants |
| `databricks-compute` | Dev interactive cluster, SQL warehouse |
| `databricks-workload-sp` | Azure AD SP, federated credentials, Key Vault secret, UC grants |

See [`docs/reference/modules.md`](../docs/reference/modules.md) for per-module variable reference.

---

## Environment Differences (Dev vs Prod)

| Setting | Dev | Prod |
|---|---|---|
| `enable_purge_protection` | `false` | `true` |
| `log_retention_days` | `30` | `90` |
| `storage_replication_type` | `LRS` | `ZRS` or `GRS` |
| `enable_spot_instances` | `true` | environment-specific |
| `interactive_max_clusters_per_user` | `5` | `2` |
| `unity_catalog_metastore_mode` | `auto` | `existing` |
| `enable_workload_sp` | optional | `true` (recommended) |
| CI/CD SP registration | optional | required |

---

## Security Notes

- `*.tfvars` files are **committed to git** — `.example` files serve as documentation templates for new projects. `backend.hcl` is **gitignored**
- Enable `enable_purge_protection = true` in prod to prevent Key Vault accidental deletion
- Set `enable_public_access = false` + Private Link for production network hardening
- Set `enable_ip_access_lists = true` + `governance_allowed_ips` to restrict workspace access by IP
- The CI/CD SP is granted minimum `USER` workspace permission only — never `ADMIN`

See [`docs/guides/security-hardening.md`](../docs/guides/security-hardening.md) for the full security checklist.
