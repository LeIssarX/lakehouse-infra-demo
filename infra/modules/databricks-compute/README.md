# Module: databricks-compute

Provisions a single **interactive cluster** in a Databricks workspace. Called with `for_each` from `infra/compute.tf` so that multiple clusters can be provisioned from the `var.clusters` map variable.

## Resources

| Resource | Condition |
|----------|-----------|
| `databricks_cluster.this` | Always |

### Cluster characteristics

- **Data security mode:** `SINGLE_USER` (required for Unity Catalog row-level security)
- **Autoscale:** `min_workers` – `max_workers` (defaults: 1–4)
- **Availability:** `SPOT_WITH_FALLBACK_AZURE` when `enable_spot_instances = true` (cost-optimised); `ON_DEMAND_AZURE` otherwise
- **Auto-termination:** configurable (default: 30 min idle)
- **Cluster policy:** supplied from the governance module via `cluster_policy_id`
- **Naming:** `{environment}-{name}` (e.g. `dev-engineering`, `prod-ml`)

## Usage

This module is invoked from `infra/compute.tf` using `for_each` over the `var.clusters` map:

```hcl
# infra/compute.tf
module "cluster" {
  for_each = var.clusters

  source = "./modules/databricks-compute"

  providers = {
    databricks = databricks.workspace
  }

  name                     = each.key
  environment              = var.environment
  owner                    = each.value.owner
  node_type                = each.value.node_type
  min_workers              = each.value.min_workers
  max_workers              = each.value.max_workers
  spark_version            = each.value.spark_version
  data_security_mode       = each.value.data_security_mode
  enable_spot_instances    = each.value.enable_spot
  auto_termination_minutes = each.value.auto_termination_minutes
  cluster_policy_id        = try(module.governance.cluster_policy_ids[each.value.policy_key], null)
  tags                     = var.tags

  depends_on = [module.governance, module.unity_catalog]
}
```

Operators configure clusters via the `clusters` variable in `dev.tfvars` or `prod.tfvars`:

```hcl
# infra/envs/dev/dev.tfvars
clusters = {
  "engineering" = { owner = "alice@company.com" }
  "ml"          = { owner = "bob@company.com", node_type = "Standard_E16_v3", policy_key = "ml_clusters" }
}

# infra/envs/prod/prod.tfvars — no interactive clusters in production
clusters = {}
```

## Variables

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `name` | `string` | **Yes** | — | Logical name for this cluster. Combined with environment for the display name: `{environment}-{name}` |
| `environment` | `string` | **Yes** | — | Environment name (`dev` or `prod`) |
| `owner` | `string` | **Yes** | — | Single-user owner email. The cluster is bound to this identity. Must be a valid workspace member. |
| `cluster_policy_id` | `string` | No | `null` | Policy ID from `databricks-governance` module. Null = no policy applied. |
| `node_type` | `string` | No | `Standard_DS4_v2` | Azure VM SKU for driver and worker nodes |
| `min_workers` | `number` | No | `1` | Autoscale minimum worker count |
| `max_workers` | `number` | No | `4` | Autoscale maximum worker count |
| `auto_termination_minutes` | `number` | No | `30` | Idle shutdown timeout in minutes (10–10000) |
| `enable_spot_instances` | `bool` | No | `true` | Use Azure Spot VMs with fallback to on-demand |
| `spark_version` | `string` | No | `auto:latest-lts` | Databricks Runtime version |
| `data_security_mode` | `string` | No | `SINGLE_USER` | Unity Catalog data security mode |
| `tags` | `map(string)` | No | `{}` | Tags applied to cluster `custom_tags` |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_id` | Databricks cluster ID |
| `cluster_url` | Databricks UI URL for the cluster configuration page |

The root module aggregates these as maps:

```hcl
output "cluster_ids"  { value = { for k, v in module.cluster : k => v.cluster_id } }
output "cluster_urls" { value = { for k, v in module.cluster : k => v.cluster_url } }
```

## Notes

- This module requires the workspace-level Databricks provider (`databricks.workspace`), not the account-level provider.
- `data_security_mode = "SINGLE_USER"` binds the cluster to `owner`; only that user can attach notebooks or jobs to it. For shared notebook access, switch to `USER_ISOLATION` mode and remove `single_user_name`.
- SQL Warehouses are managed separately via the `databricks_sql_endpoint.warehouses` resource in `infra/sql-warehouses.tf` using the `var.sql_warehouses` map variable. They do not use this module.
- See [docs/guides/compute-clusters.md](../../../docs/guides/compute-clusters.md) for the full operator guide including policy key reference, lifecycle operations, and troubleshooting.
