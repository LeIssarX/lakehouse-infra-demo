# Production Environment

This directory contains the OpenTofu configuration for the **Production** environment of the Azure Data Lakehouse Blueprint.

## Architecture

The prod environment deploys:

- **Network**: VNet with Databricks subnets + Private Link (secured)
- **Databricks Workspace**: Premium tier with Unity Catalog
- **Storage**: One or more ADLS Gen2 accounts with GRS replication (configured via `storage_accounts`)
- **Key Vault**: Secrets management with IP restrictions
- **Unity Catalog**: Shared regional metastore, catalog, schemas, volumes, external locations
- **Governance**: Strict cluster policies, IP allow-lists, token lifetime enforcement
- **SQL Warehouses** (optional): Configured via `sql_warehouses` in `prod.tfvars`

## Production Security

Production environment enforces:

- VNet injection (no public IP on clusters)
- Private Link (private connectivity only)
- IP allow-lists (corporate network access only)
- Key Vault firewall (restricted IPs)
- GRS storage (disaster recovery)
- Spot instances disabled (higher availability, configured per cluster in `clusters` map)
- Purge protection enabled (compliance)

## 📋 Prerequisites

### Required Tools

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.10.0
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) >= 2.50.0
- [Databricks CLI](https://docs.databricks.com/dev-tools/cli/index.html) >= 0.200.0

### Azure Permissions

- **Contributor** role on target subscription
- **User Access Administrator** (for RBAC assignments)

### Configuration Files

- `infra/common.tfvars` - Global values (shared with dev)
- `infra/envs/prod/prod.tfvars` - Production-specific values

---

## 🚀 Deployment Steps

### 1. Prepare Configuration

```bash
# tfvars are already in git — edit directly
# Edit common.tfvars with your account ID, location, etc.
vim infra/common.tfvars

# Edit prod.tfvars with production-specific values
vim infra/envs/prod/prod.tfvars
```

**Key prod.tfvars configurations to review:**

- `storage_accounts` — storage configuration (replication, lifecycle, containers)
- `sql_warehouses` — which SQL warehouses to provision (size, type, auto-stop)
- `clusters` — keep as `{}` in prod; use Job Clusters via DABs for workloads
- Network ranges (ensure no conflicts with dev/other environments)
- IP allow-lists (corporate network ranges)
- Security settings (`enable_vnet_injection`, `enable_public_access`)

→ [Storage Accounts Guide](../../../docs/guides/storage-accounts.md)
→ [SQL Warehouses Guide](../../../docs/guides/sql-warehouses.md)
→ [Compute Clusters Guide](../../../docs/guides/compute-clusters.md)

### 2. Authentication Setup

```bash
# Set Azure credentials
export ARM_CLIENT_ID="your-prod-sp-client-id"
export ARM_CLIENT_SECRET="your-prod-sp-secret"
export ARM_TENANT_ID="your-tenant-id"
export ARM_SUBSCRIPTION_ID="your-prod-subscription-id"

# Verify authentication
az account show
```

**⚠️ IMPORTANT:** Use dedicated **production service principal** with appropriate RBAC roles. Never use personal credentials for prod deployments.

### 3. Create Remote State Backend

```bash
# Generate backend configuration
./scripts/create-backend.sh prod

# This creates infra/envs/prod/backend.hcl (gitignored — do not commit)
```

### 4. Initialize OpenTofu

```bash
cd infra

# Initialize with backend
tofu init -backend-config=envs/prod/backend.hcl -reconfigure

# Verify configuration
tofu validate -var-file=common.tfvars -var-file=envs/prod/prod.tfvars
```

### 5. Plan Deployment

```bash
# Generate execution plan (run from infra/)
tofu plan \
  -var-file=common.tfvars \
  -var-file=envs/prod/prod.tfvars \
  -out=prod.tfplan

# Review plan carefully before applying to production!
```

### 6. Deploy to Production

```bash
# Apply configuration
tofu apply prod.tfplan

# Deployment takes ~15-20 minutes
```

### 7. Verify Deployment

```bash
# Show all outputs
tofu output

# Key outputs to check:
tofu output -raw databricks_workspace_url     # Workspace URL
tofu output storage_account_names            # Map of all storage account names
tofu output sql_warehouse_ids                # Map of SQL warehouse IDs
tofu output cluster_ids                      # Map of cluster IDs (empty map in prod = expected)
```

---

## Day-2 Operations: Compute & Storage

### Adding a SQL Warehouse

Add an entry to `sql_warehouses` in `prod.tfvars` and apply:

```hcl
sql_warehouses = {
  "engineering" = { size = "Small", enable_serverless = true }
  "analytics"   = { size = "Medium", auto_stop_mins = 15 }    # new
}
```

```bash
./scripts/tofu-wrapper.sh prod plan   # review change
./scripts/tofu-wrapper.sh prod apply
tofu output sql_warehouse_jdbc_urls   # get JDBC URLs for BI tools
```

### Adding a Storage Account

Add an entry to `storage_accounts` in `prod.tfvars` (the "lake" key must always remain):

```hcl
storage_accounts = {
  "lake"   = { replication_type = "GRS", enable_lifecycle_policy = true, ... }
  "secure" = { containers = ["pii", "restricted"], replication_type = "GRS" }  # new
}
```

The new account's containers are automatically registered as Unity Catalog External Locations.

→ [docs/guides/storage-accounts.md](../../../docs/guides/storage-accounts.md)

## Day-2 Operations

### Making Changes

```bash
# Always plan before applying (run from infra/)
tofu plan -var-file=common.tfvars -var-file=envs/prod/prod.tfvars

# Review changes carefully
tofu apply -var-file=common.tfvars -var-file=envs/prod/prod.tfvars
```

### Viewing State

```bash
# List resources
tofu state list

# Show specific resource
tofu state show azurerm_resource_group.main
```

### Drift Detection

```bash
# Detect configuration drift (run from infra/)
tofu plan -var-file=common.tfvars -var-file=envs/prod/prod.tfvars

# Should show "No changes" if no drift
```

---

## 📊 Monitoring & Alerts

### Post-Deployment Setup

1. **Configure monitoring:**
   - Enable Azure Monitor for workspace
   - Set up cost alerts
   - Configure log analytics

2. **Unity Catalog:**
   - Enable system tables
   - Configure audit logging
   - Set up data lineage tracking

3. **Security:**
   - Review IP allow-lists
   - Validate Private Link connectivity
   - Test DR procedures

---

## 🆘 Troubleshooting

### Common Issues

#### 1. Plan Shows Unexpected Changes

```bash
# Check for manual changes in Azure Portal
tofu refresh -var-file=../../common.tfvars -var-file=../prod.tfvars

# Compare with state
tofu plan -var-file=../../common.tfvars -var-file=../prod.tfvars
```

#### 2. Backend State Lock

```bash
# If deployment was interrupted
# Manually unlock (use with caution!)
tofu force-unlock <lock-id>
```

#### 3. VNet Injection Issues

- Verify subnet configurations
- Check NSG rules
- Validate service endpoints
- Review Private Link setup

---

## 🔐 Security Best Practices

1. **Never commit secrets:**
   - Use Azure Key Vault for runtime secrets
   - Use GitHub Secrets for CI/CD credentials
   - Keep real secrets (passwords, tokens) in Azure Key Vault, never in tfvars

2. **Principle of least privilege:**
   - Production service principal should have minimal permissions
   - Use separate SPs for dev and prod
   - Regularly rotate credentials

3. **Change management:**
   - All changes via CI/CD pipeline
   - Require PR approval via branch protection on main
   - Test in dev first

4. **Audit trail:**
   - Enable Azure Activity Log
   - Configure Databricks audit logs
   - Monitor Unity Catalog system tables

---

## 📚 Related Documentation

- [Getting Started Guide](../../../docs/guides/getting-started.md)
- [CI/CD Setup](../../../docs/guides/cicd-setup.md)
- [Module Reference](../../../docs/reference/modules.md)
- [Customization Guide](../../../docs/reference/customization.md)

---

## ⚠️ IMPORTANT NOTES

1. **Production deployments require PR approval** via branch protection rules (see docs/guides/branch-protection-setup.md)
2. **Always test changes in dev first** before applying to prod
3. **Backup important data** before major infrastructure changes
4. **Monitor costs** - production workloads can be expensive
5. **Follow change management procedures** - document all changes
6. **Disaster recovery** - verify regular backups and test restore procedures

---

## 🎯 Next Steps

1. ✅ Deploy baseline infrastructure
2. 📊 Configure monitoring and alerting
3. 👥 Set up user access and groups
4. 📝 Create production workloads (Databricks Asset Bundles)
5. 🔄 Set up CI/CD pipelines
6. 📚 Document operational procedures
7. 🔒 Conduct security review
