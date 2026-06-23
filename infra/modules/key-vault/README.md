# Key Vault Module

This module creates Azure Key Vault for secure secrets management in the lakehouse platform.

## Features

- **RBAC-based access control** (recommended over access policies)
- **Soft delete** and **purge protection**
- **Private endpoint** support
- **Network ACLs** for IP-based restrictions
- Integration with **Databricks Secret Scopes**
- **Diagnostic logging** support

## Resources Created

- `azurerm_key_vault` - Key Vault instance
- `azurerm_role_assignment` - RBAC role assignments
- `azurerm_private_endpoint` (optional) - Private endpoint
- `azurerm_monitor_diagnostic_setting` (optional) - Audit logging

## Usage

```hcl
module "key_vault" {
  source = "../../modules/key-vault"

  resource_group_name = var.resource_group_name
  location            = var.location
  environment         = var.environment
  
  # Naming (will auto-generate if not provided)
  key_vault_name      = "kv-lakehouse-dev"
  
  # RBAC assignments
  rbac_assignments = {
    admins = {
      principal_id = data.azuread_group.platform_admins.object_id
      role         = "Key Vault Administrator"
    }
    databricks = {
      principal_id = module.databricks_workspace.access_connector_principal_id
      role         = "Key Vault Secrets User"
    }
  }
  
  # Network security
  enable_public_access = false
  allowed_ip_ranges    = ["1.2.3.4/32"]
  
  tags = var.tags
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| resource_group_name | Name of the resource group | string | Yes |
| location | Azure region | string | Yes |
| environment | Environment (dev/prod/sandbox) | string | Yes |
| key_vault_name | Name of the Key Vault (optional, auto-generated) | string | No |
| sku_name | SKU (standard/premium) | string | No |
| rbac_assignments | Map of RBAC role assignments | map(object) | No |
| enable_public_access | Enable public network access | bool | No |
| allowed_ip_ranges | Allowed IP ranges for public access | list(string) | No |
| enable_soft_delete | Enable soft delete | bool | No |
| soft_delete_retention_days | Soft delete retention (7-90 days) | number | No |
| enable_purge_protection | Enable purge protection (irreversible) | bool | No |
| tags | Resource tags | map(string) | No |

## Outputs

| Name | Description |
|------|-------------|
| key_vault_id | Key Vault resource ID |
| key_vault_name | Key Vault name |
| key_vault_uri | Key Vault URI |

## Databricks Integration

### Creating a Secret Scope

After Key Vault is created, connect it to Databricks:

```bash
# Using Azure-backed secret scope
databricks secrets create-scope \
  --scope kv-backed-scope \
  --scope-backend-type AZURE_KEYVAULT \
  --resource-id /subscriptions/.../vaults/kv-lakehouse-dev \
  --dns-name https://kv-lakehouse-dev.vault.azure.net/

# Access secrets in notebooks
dbutils.secrets.get(scope="kv-backed-scope", key="my-secret")
```

### RBAC Roles for Databricks

- **Key Vault Secrets User**: Read secrets only (recommended for workloads)
- **Key Vault Secrets Officer**: Manage secrets
- **Key Vault Administrator**: Full admin access

## Network Access Behavior

| Scenario | `enable_public_access` | `allowed_ip_ranges` | Result |
|----------|----------------------|---------------------|--------|
| Dev (default) | `true` | `[]` | Open access — all IPs allowed |
| Restricted public | `true` | `["10.0.0.0/8"]` | Only listed IPs + Azure services |
| Private endpoint only | `false` | (ignored) | All public access blocked |

**Important:** `bypass = "AzureServices"` allows Databricks Access Connector and other Azure
services, but does **not** cover GitHub Actions runners (GitHub-hosted, not Azure-hosted).
If you set `allowed_ip_ranges` in dev, also add GitHub Actions IPs to avoid CI/CD failures:

```hcl
# dev.tfvars — if IP restriction is needed in dev:
key_vault_allowed_ips = [
  "10.0.0.0/8",    # Your corporate network
  # GitHub Actions meta IP ranges — see: https://api.github.com/meta (ranges.actions)
  # Example (verify current ranges before use):
  # "4.148.0.0/16",
  # "20.1.0.0/16",
]
```

For production, the recommended approach is `enable_public_access = false` with a private endpoint,
which makes the IP allowlist irrelevant for external access.

## Security Best Practices

✅ **DO:**

- Use RBAC instead of access policies
- Enable soft delete and purge protection in production
- Use private endpoints for production workloads
- Enable diagnostic logging to Log Analytics
- Rotate secrets regularly
- Use separate Key Vaults for dev/prod

❌ **DON'T:**

- Store Key Vault secrets in version control
- Use same Key Vault across environments
- Grant overly broad permissions
- Disable soft delete in production

## Common Secrets to Store

```hcl
# Example secrets for lakehouse platform
resource "azurerm_key_vault_secret" "example" {
  name         = "databricks-token"
  value        = var.databricks_token
  key_vault_id = module.key_vault.key_vault_id
}

# Other common secrets:
# - Storage account connection strings (backup)
# - Service principal credentials
# - API keys for external services
# - JWT signing keys
# - Database passwords
```

## TODO: Post-Deployment Configuration

After deploying Key Vault:

1. **Create Databricks-backed secret scope**

   ```bash
   databricks secrets create-scope --scope kv-backed-scope ...
   ```

2. **Add secrets**
   - Via Azure Portal, CLI, or Terraform
   - Never commit secrets to Git

3. **Configure audit logging**
   - Send logs to Log Analytics workspace
   - Set up alerts for secret access

4. **Test secret access**
   - Verify Databricks can read secrets
   - Test RBAC permissions
