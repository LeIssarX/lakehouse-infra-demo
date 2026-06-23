# Development Environment

This directory contains the OpenTofu configuration for the **Development** environment of the Azure Data Lakehouse Blueprint.

## Architecture

The dev environment deploys:

- **Network**: VNet with Databricks subnets (optional, disabled by default in dev)
- **Databricks Workspace**: Premium tier with Unity Catalog
- **Storage**: One or more ADLS Gen2 accounts (configured via `storage_accounts` in `dev.tfvars`)
- **Key Vault**: Secrets management
- **Unity Catalog**: Metastore, catalogs, schemas, volumes, external locations
- **Governance**: Cluster policies, token policies, IP access lists
- **Compute** (optional): Interactive clusters and SQL Warehouses (configured via `clusters` and `sql_warehouses`)

## 📋 Prerequisites

### Required Tools

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.10.0
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) >= 2.50.0
- [Databricks CLI](https://docs.databricks.com/dev-tools/cli/index.html) >= 0.200.0

### Azure Permissions

- **Contributor** role on target subscription
- **User Access Administrator** (for RBAC assignments)

### Unity Catalog (Auto-UC)

- No manual setup required - metastore is auto-provisioned
- Single manual step: Entra ID Global Admin activates Account Console
- See [docs/account-console-setup.md](../../../docs/account-console-setup.md) for details

### CI/CD and SCIM (Recommended)

- For automated deployments and user sync, follow [docs/cicd-setup.md](../../../docs/cicd-setup.md)
- Includes OIDC setup (no secrets to rotate)
- Includes SCIM setup (automatic user/group provisioning)

---

---

## 🚀 Deployment Steps

### 1. Authentication Setup

#### Option A: Azure CLI (For Local Development)

```bash
# Login to Azure
az login

# Set subscription (if you have multiple)
az account set --subscription YOUR_SUBSCRIPTION_ID

# Verify
az account show
```

#### Option B: OIDC for CI/CD (Recommended for GitHub Actions)

See [docs/cicd-setup.md](../../../docs/cicd-setup.md) for complete setup:

- No secrets to rotate
- More secure than service principals
- Automated federated credential configuration

#### Option B: Azure CLI (For Local Development)

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription YOUR_SUBSCRIPTION_ID

# Databricks will use Azure CLI auth automatically
```

### 2. Configure Variables

```bash
# Navigate to repo root
cd /path/to/azure-data-lakehouse-blueprint

# tfvars are already in git — edit directly
# IMPORTANT: Set databricks_account_id, location, tags, etc.
vim infra/common.tfvars

# Edit dev.tfvars with environment-specific values
vim infra/envs/dev/dev.tfvars
```

**Global Variables (common.tfvars):**

- `databricks_account_id` - Your Databricks account ID
- `location` - Azure region (e.g., "westeurope")
- `allowed_node_types` - VM types for clusters
The backend is **auto-generated** by the create-backend.sh script:

```bash
# Create backend infrastructure and generate backend.hcl
./scripts/create-backend.sh dev

# This creates:
# - Resource group: rg-terraform-state-dev
# - Storage account: sttfstatedev<suffix>
# - Container: tfstate
# - File: infra/envs/dev/backend.hcl (auto-generated, gitignored — do not commit)
```

### 4. Initialize OpenTofu

```bash
cd infra
tofu init -backend-config=envs/dev/backend.hcl -reconfigure
```

### 5. Plan & Apply

#### Option 1: Direct Commands

```bash
# Review what will be created (run from infra/)
tofu plan -var-file=common.tfvars -var-file=envs/dev/dev.tfvars -out=tfplan

# Apply changes
tofu apply tfplan
```

#### Option 2: Using Wrapper Script (Recommended)

```bash
# From repo root
./scripts/tofu-wrapper.sh dev plan   # Review changes
./scripts/tofu-wrapper.sh dev apply  # Deploy

# Wrapper automatically loads both var-files
```

### 6. Verify Deployment

```bash
# Show all outputs
tofu output

# Key outputs to check:
tofu output -raw databricks_workspace_url    # Workspace URL
tofu output storage_account_names           # Map of storage account names
tofu output cluster_ids                     # Map of provisioned cluster IDs (if any)
tofu output sql_warehouse_ids               # Map of provisioned SQL warehouse IDs (if any)

# Test Databricks connection
databricks configure --token --host $(tofu output -raw databricks_workspace_url)

# List Unity Catalog resources
databricks catalogs list
databricks schemas list --catalog lakehouse_dev
```

## 📊 Cost Estimation

**Estimated monthly cost** (with moderate usage):

| Resource | Cost/Month (USD) |
|----------|------------------|
| Databricks Workspace | $0 (base) + $0.55/DBU |
| Databricks Compute (dev) | ~$200-500 |
| Storage (ADLS Gen2 Premium) | ~$50-100 |
| Key Vault | ~$1 |
| Network (VNet) | ~$5 |
| **Total** | **~$250-600** |

> **Note**: Costs vary based on compute usage. Use serverless and auto-termination to minimize costs.

## Post-Deployment Tasks

### 1. Verify Key Vault Secret Scope

Secret scope is automatically created by OpenTofu:

```bash
databricks secrets list-scopes
# Expected: kv-backed-scope (AZURE_KEYVAULT)
```

### 2. Verify Azure AD Groups

```bash
az ad group list \
  --query "[?contains(displayName, 'Databricks-')].{Name:displayName}" \
  -o table
```

Add users to groups:
```bash
az ad group member add --group "Databricks-Engineers-Dev" --member-id <user-object-id>
```

### 3. Provision a Cluster (Optional)

Add an entry to `clusters` in `dev.tfvars`, then apply:

```hcl
clusters = {
  "engineering" = { owner = "your.email@company.com" }
}
```

```bash
./scripts/tofu-wrapper.sh dev apply
tofu output cluster_ids   # shows: { "engineering" = "0123-456789-abc" }
```

### 4. Provision a SQL Warehouse (Optional)

```hcl
sql_warehouses = {
  "shared" = {}
}
```

```bash
./scripts/tofu-wrapper.sh dev apply
tofu output sql_warehouse_jdbc_urls   # shows JDBC connection URL
```

## Configuration Options

### Provisioning Compute Resources

**Interactive Clusters** — add entries to `clusters` in `dev.tfvars`:

```hcl
clusters = {
  "engineering" = { owner = "alice@company.com" }
  "ml"          = { owner = "bob@company.com", node_type = "Standard_E8_v3", policy_key = "ml_clusters" }
}
```

Remove an entry and run `tofu apply` to deprovision the cluster.

**SQL Warehouses** — add entries to `sql_warehouses` in `dev.tfvars`:

```hcl
sql_warehouses = {
  "shared"    = {}
  "analytics" = { size = "Medium", auto_stop_mins = 15 }
}
```

See `dev.tfvars.example` for all available fields and options, or the full guide at
→ [docs/guides/compute-clusters.md](../../../docs/guides/compute-clusters.md)
→ [docs/guides/sql-warehouses.md](../../../docs/guides/sql-warehouses.md)

### Configuring Storage Accounts

The default configuration provisions one ADLS Gen2 account. Additional accounts can be
added for domain separation (PII isolation) or billing isolation:

```hcl
storage_accounts = {
  "lake" = {                           # Required — Metastore root
    containers       = ["metastore", "landing", "raw", "curated", "core", "mart", "reporting", "sharing"]
    replication_type = "LRS"
  }
  "secure" = {                         # Optional — separate account for sensitive data
    containers = ["pii", "restricted"]
    replication_type = "ZRS"
  }
}
```

All containers in all accounts are automatically registered as Unity Catalog External Locations.

→ [docs/guides/storage-accounts.md](../../../docs/guides/storage-accounts.md)

### VNet Injection (Optional)

For production-like setup:

```hcl
# In dev.tfvars
enable_vnet_injection = true
vnet_address_space = ["10.100.0.0/16"]
public_subnet_address_prefixes = ["10.100.1.0/24"]
private_subnet_address_prefixes = ["10.100.2.0/24"]
```

### IP Access Lists (Optional)

Restrict workspace access:

```hcl
# In dev.tfvars
enable_ip_access_lists = true
governance_allowed_ips = [
  "10.0.0.0/8",       # Corporate network
  "203.0.113.0/24"    # Office IP
]
```

### Unity Catalog Metastore Configuration

The blueprint supports three metastore configuration modes via `unity_catalog_metastore_mode`:

#### Mode 1: Auto-discovery (Recommended for new workspaces)

For workspaces created **after November 9, 2023**, Databricks automatically provisions a metastore:

```hcl
# In dev.tfvars
unity_catalog_metastore_mode = "auto"
```

The module will automatically discover and use the workspace's metastore. No additional configuration needed.

#### Mode 2: Use Existing Metastore (For shared or account-limited scenarios)

When you've reached the metastore limit per region or want to share a metastore across workspaces:

```hcl
# In dev.tfvars
unity_catalog_metastore_mode = "existing"
unity_catalog_metastore_id   = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

**To find your Metastore ID:**

1. Go to [Databricks Account Console](https://accounts.azuredatabricks.net/) → Data
2. Copy the Metastore ID from the list
3. Or use: `databricks unity-catalog metastores list` (requires account admin)

#### Mode 3: Create New Metastore (For legacy workspaces or manual setup)

For workspaces created **before November 2023** or when explicitly creating a new metastore:

```hcl
# In dev.tfvars
unity_catalog_metastore_mode = "create"
unity_catalog_metastore_name = "lakehouse_dev_metastore"
```

**Prerequisites:**

- Databricks account admin access
- No existing metastore in the region (check account limits)

## 🐛 Troubleshooting

### Authentication Issues

```bash
# Verify Azure CLI login
az account show

# Test Databricks auth
databricks workspace list

# Check environment variables
echo $ARM_CLIENT_ID
echo $ARM_SUBSCRIPTION_ID
```

### Databricks Provider Errors

```bash
# Clear provider cache
rm -rf .terraform
rm .terraform.lock.hcl
tofu init -backend-config=backend.hcl -upgrade
```

### State Lock Issues

```bash
# Force unlock (use with caution)
tofu force-unlock LOCK_ID
```

### Unity Catalog Assignment Failures

If metastore assignment fails:

1. Check Access Connector has correct RBAC on storage
2. Verify storage account allows Databricks managed identity
3. Check if metastore already assigned to workspace

## 🧹 Cleanup

To destroy all resources:

```bash
# Show what will be destroyed
tofu plan -destroy

# Destroy (careful!)
tofu destroy
```

**⚠️ Warning**: This will delete:

- All data in storage accounts
- All Unity Catalog metadata
- All Databricks compute resources
- Network configuration

## 📚 Related Documentation

- [../../../docs/guides/greenfield-deployment.md](../../../docs/guides/greenfield-deployment.md) - Full deployment guide
- [../../../docs/reference/architecture.md](../../../docs/reference/architecture.md) - Architecture overview
- [../../modules/](../../modules/) - Module documentation
- [../prod/](../prod/) - Production environment config

## 🆘 Getting Help

- GitHub Issues: [ruhragency/azure-data-lakehouse-blueprint/issues](https://github.com/ruhragency/azure-data-lakehouse-blueprint/issues)
- Databricks Community: [community.databricks.com](https://community.databricks.com/)
- Azure Support: [azure.microsoft.com/support](https://azure.microsoft.com/support/)

## ✅ Checklist

- [ ] Azure CLI installed and logged in
- [ ] Terraform >= 1.10.0 installed
- [ ] Databricks account ID obtained
- [ ] dev.tfvars configured
- [ ] Backend storage created
- [ ] Authentication configured
- [ ] tofu init successful
- [ ] tofu plan reviewed
- [ ] tofu apply completed
- [ ] Databricks CLI configured
- [ ] Secret scope created
- [ ] Test table created
- [ ] Cluster policy tested

---

**Next**: Deploy workloads using [Databricks Asset Bundles](../../../workloads/README.md)
