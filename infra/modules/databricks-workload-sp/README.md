# Databricks Workload Service Principal Module

## Overview

This module automates the creation and configuration of Azure AD service principals for running Databricks workloads (jobs, pipelines, workflows) in production environments.

**Key Features:**

- ✅ Creates Azure AD application and service principal
- ✅ Registers SP in Databricks with least-privilege permissions
- ✅ Grants Unity Catalog permissions (catalog, schema, volume levels)
- ✅ Optionally stores credentials in Azure Key Vault
- ✅ Outputs credentials for CI/CD integration
- ✅ Follows security best practices (no cluster create by default, limited scope)

## Use Cases

### Production Workloads

- **Databricks Jobs**: Scheduled ETL jobs running as dedicated identity
- **Delta Live Tables Pipelines**: Lakeflow pipelines with isolated permissions
- **Workflows**: Multi-task workflows requiring specific UC grants
- **SQL Warehouses**: Query execution under service identity

### Development Workloads

**Not recommended** — dev workloads should run as user identity for easier debugging and personal namespace isolation.

## Architecture

```text
Azure AD                    Databricks Account              Unity Catalog
┌─────────────┐            ┌──────────────────┐           ┌─────────────┐
│ Application │            │ Service Principal│           │ Catalog     │
│ (Client ID) │───────────>│ (Registered)     │──────────>│ Grants      │
│             │            │                  │           │             │
│ Secret      │            │ Workspace Access │           │ Schema      │
│ (1yr exp)   │            │ (USER/no perm)   │           │ Grants      │
└─────────────┘            └──────────────────┘           └─────────────┘
      │                              │
      │                              │
      └──────> Key Vault ────────────┘
              (Optional storage)
```

## Usage

### Basic Example: Production Pipeline

```hcl
module "pipeline_sp" {
  source = "../../modules/databricks-workload-sp"

  service_principal_name = "Lakehouse Pipeline (prod)"
  environment            = "prod"

  # Unity Catalog grants for medallion architecture
  catalog_grants = {
    "lakehouse_prod" = ["USE CATALOG"]
  }

  schema_grants = {
    "lakehouse_prod.bronze" = ["USE SCHEMA", "SELECT"]
    "lakehouse_prod.silver" = ["USE SCHEMA", "SELECT", "MODIFY"]
    "lakehouse_prod.gold"   = ["USE SCHEMA", "SELECT", "MODIFY"]
  }

  # Optional: Enable SQL access for queries
  enable_sql_access = true

  # Security: No cluster create (use job clusters)
  allow_cluster_create = false
}

output "pipeline_sp_client_id" {
  value = module.pipeline_sp.application_id
}

output "pipeline_sp_client_secret" {
  value     = module.pipeline_sp.client_secret
  sensitive = true
}
```

### Advanced Example: With Key Vault Storage

```hcl
module "ml_pipeline_sp" {
  source = "../../modules/databricks-workload-sp"

  service_principal_name = "ML Training Pipeline (prod)"
  environment            = "prod"

  # Store credentials in Key Vault
  store_credentials_in_keyvault = true
  key_vault_id                  = module.key_vault.key_vault_id
  secret_prefix                 = "ml-pipeline-sp"

  # Grant access to ML catalog
  catalog_grants = {
    "ml_prod" = ["USE CATALOG"]
  }

  schema_grants = {
    "ml_prod.features" = ["USE SCHEMA", "SELECT"]
    "ml_prod.models"   = ["USE SCHEMA", "SELECT", "MODIFY"]
  }

  # Enable cluster creation for ML workloads
  allow_cluster_create = true
  enable_sql_access    = false

  tags = ["ml", "production"]
}
```

## Integration with Databricks Asset Bundles

After creating the SP via OpenTofu, use it in your `databricks.yml`:

```yaml
variables:
  prod_service_principal:
    description: "Application ID of the pipeline service principal"
    default: "REPLACE_WITH_SP_APPLICATION_ID"

targets:
  prod:
    mode: production

    # Run as the automated service principal
    run_as:
      service_principal_name: ${var.prod_service_principal}

    resources:
      pipelines:
        customers_pipeline:
          name: "customers_pipeline"
          catalog: "lakehouse_prod"
```

**Setting the application ID:**

```bash
# Option 1: Environment variable
export DATABRICKS_PROD_SP="<client-id-from-tofu-output>"
databricks bundle deploy -t prod --var prod_service_principal=$DATABRICKS_PROD_SP

# Option 2: In CI/CD (GitHub Actions)
databricks bundle deploy -t prod --var prod_service_principal=${{ secrets.PROD_PIPELINE_SP_CLIENT_ID }}
```

## Permissions Model

### Least Privilege (Default)

```hcl
allow_cluster_create          = false  # Use job clusters, not interactive
allow_instance_pool_create    = false  # Admins manage pools
workspace_permission          = null   # No workspace-level access
enable_sql_access             = true   # SQL queries allowed
```

### Extended Permissions (ML/Advanced Workloads)

```hcl
allow_cluster_create = true   # For custom compute requirements
workspace_permission = "USER" # Basic workspace functionality
```

## Security Best Practices

1. **Rotate secrets regularly**: Set `client_secret_expiration = "4380h"` (6 months) and rotate before expiry
2. **Store secrets in Key Vault**: Enable `store_credentials_in_keyvault = true`
3. **Use dedicated SPs per workload**: Don't share SPs across pipelines
4. **Grant minimal UC permissions**: Only what the pipeline needs
5. **Disable cluster creation**: Unless specifically required for interactive workloads
6. **Monitor usage**: Check Databricks audit logs for SP activity

## Credential Management

### Local Development

```bash
# Get credentials from OpenTofu output
cd infra/envs/prod
tofu output -json | jq '.pipeline_sp_client_id.value'
tofu output -raw pipeline_sp_client_secret  # Sensitive

# Configure Databricks CLI
export DATABRICKS_HOST="https://adb-XXXXXXXXX.azuredatabricks.net"
export DATABRICKS_CLIENT_ID="<client-id>"
export DATABRICKS_CLIENT_SECRET="<client-secret>"
```

### CI/CD (GitHub Actions)

Store secrets as GitHub repository secrets:

```bash
# Add to GitHub secrets
gh secret set PROD_PIPELINE_SP_CLIENT_ID --body "<client-id>"
gh secret set PROD_PIPELINE_SP_CLIENT_SECRET --body "<client-secret>"
```

Use in workflow:

```yaml
- name: Deploy bundle
  env:
    DATABRICKS_HOST: ${{ vars.DATABRICKS_PROD_WORKSPACE_URL }}
    DATABRICKS_CLIENT_ID: ${{ secrets.PROD_PIPELINE_SP_CLIENT_ID }}
    DATABRICKS_CLIENT_SECRET: ${{ secrets.PROD_PIPELINE_SP_CLIENT_SECRET }}
  run: |
    databricks bundle deploy -t prod --var prod_service_principal=${{ secrets.PROD_PIPELINE_SP_CLIENT_ID }}
```

## Troubleshooting

### SP not appearing in Databricks

**Symptom:** Service principal created in Azure AD but not visible in Databricks UI

**Solutions:**

1. Verify account-level provider is configured correctly
2. Check Databricks Account Admin access
3. Wait 1-2 minutes for sync

### Permission denied errors

**Symptom:** `403 Forbidden` when running workload

**Solutions:**

1. Verify Unity Catalog grants are applied: `databricks grants get catalog <catalog>`
2. Check schema-level permissions
3. Ensure SP has `enable_sql_access = true` if running SQL queries

### Client secret expired

**Symptom:** Authentication failures

**Solutions:**

1. Rotate secret: `tofu taint module.pipeline_sp.azuread_application_password.workload[0]`
2. Run `tofu apply` to generate new secret
3. Update GitHub secrets / Key Vault
4. Redeploy workloads

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| service_principal_name | Display name for the SP | string | - | yes |
| environment | Environment name | string | - | yes |
| allow_cluster_create | Allow cluster creation | bool | false | no |
| allow_instance_pool_create | Allow pool creation | bool | false | no |
| enable_sql_access | Enable SQL access | bool | true | no |
| workspace_permission | Workspace permission level | string | null | no |
| catalog_grants | Catalog-level grants | map(list(string)) | {} | no |
| schema_grants | Schema-level grants | map(list(string)) | {} | no |
| volume_grants | Volume-level grants | map(list(string)) | {} | no |
| store_credentials_in_keyvault | Store in Key Vault | bool | false | no |
| key_vault_id | Key Vault resource ID | string | null | no |
| client_secret_expiration | Secret expiration duration | string | "8760h" | no |

## Outputs

| Name | Description |
|------|-------------|
| application_id | Azure AD client ID (use in bundles) |
| client_secret | Client secret for authentication (sensitive) |
| databricks_sp_id | Databricks internal SP ID |
| object_id | Azure AD object ID |

## Examples

See `infra/envs/prod/main.tf` for production usage example.

---

## Testing

This module includes comprehensive testing documentation as part of the centralized testing framework.

**Quick Validation:**

```bash
# From repository root
cd infra/modules/databricks-workload-sp
tofu fmt -check && tofu init -backend=false && tofu validate
```

**Comprehensive Testing:**

See **[docs/testing/modules/databricks-workload-sp.md](../../../docs/testing/modules/databricks-workload-sp.md)** for:

- 10 detailed test scenarios
- Expected outcomes for each test
- Troubleshooting guide
- Integration testing
- Credential rotation testing

**Quick Start:**

- [Testing Quick Start Guide](../../../docs/testing/quick-start.md)
- [Testing Framework](../../../docs/testing/framework.md)

---

**Related Documentation:**

- [Unity Catalog Grants Module](../databricks-grants/README.md)
- [Bundle Deployment Guide](../../../../workloads/example-lakeflow-pipeline/README.md)
- [CI/CD Setup](../../../../docs/guides/cicd-setup.md)
