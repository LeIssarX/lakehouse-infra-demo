# Databricks SCIM Integration Module

Automates Azure AD SCIM provisioning setup for Databricks workspaces.

> **📌 Note:** This module is **optional**. SCIM integration requires Entra ID P1/P2 licenses and a Databricks Account ID. For deployment without SCIM, see [Deployment Options](../../../README.md#-deployment-options) in the main README.

## Overview

This module automates most of the SCIM configuration process:

### Automated by OpenTofu

- ✅ Azure AD Application Registration for SCIM
- ✅ Service Principal creation
- ✅ API permissions configuration (User.Read.All, GroupMember.Read.All)
- ✅ Azure AD group assignments
- ✅ Azure AD user assignments

### Manual Steps Required

- ⚠️ **SCIM token generation** in Databricks Account Console (API limitation)
- ⚠️ **Enterprise Application provisioning setup** in Azure Portal (Gallery App)
- ⚠️ **Admin consent** for API permissions

> **Why manual?** Azure AD Enterprise Applications (Gallery Apps) and Databricks Account-level SCIM tokens don't have full OpenTofu provider support yet. The module minimizes manual work to 3 quick steps.

## Usage

### Example: Dev Environment with Groups

```hcl
# Fetch existing Azure AD groups
data "azuread_group" "databricks_admins" {
  display_name     = "Databricks-Admins"
  security_enabled = true
}

data "azuread_group" "databricks_users" {
  display_name     = "Databricks-Users"
  security_enabled = true
}

# Configure SCIM provisioning
module "databricks_scim" {
  source = "../../modules/databricks-scim"

  application_name        = "Databricks SCIM - Dev"
  databricks_account_id   = var.databricks_account_id

  assigned_groups = {
    admins = {
      object_id    = data.azuread_group.databricks_admins.object_id
      display_name = data.azuread_group.databricks_admins.display_name
    }
    users = {
      object_id    = data.azuread_group.databricks_users.object_id
      display_name = data.azuread_group.databricks_users.display_name
    }
  }

  tags = ["dev", "databricks", "scim"]
}

# Output instructions for manual steps
output "scim_setup_manual_steps" {
  value = module.databricks_scim.manual_steps_required
}
```

### Example: Assign Individual Users

```hcl
data "azuread_user" "john" {
  user_principal_name = "john.doe@company.com"
}

module "databricks_scim" {
  source = "../../modules/databricks-scim"

  application_name      = "Databricks SCIM - Prod"
  databricks_account_id = var.databricks_account_id

  assigned_users = {
    john = {
      object_id    = data.azuread_user.john.object_id
      display_name = data.azuread_user.john.display_name
    }
  }
}
```

## Manual Completion Steps

After `tofu apply`, complete these 3 steps:

### Step 1: Grant Admin Consent for API Permissions

```bash
# Get Application ID from OpenTofu output
APP_ID=$(tofu output -raw scim_application_id)

# Grant admin consent
az ad app permission admin-consent --id $APP_ID
```

Or via Azure Portal:

1. Go to **Azure AD** → **App registrations** → Your SCIM app
2. Click **API permissions** → **Grant admin consent for [Tenant]**

### Step 2: Generate SCIM Token in Databricks Account Console

1. Open <https://accounts.azuredatabricks.net>
2. Navigate to **Settings** → **User provisioning**
3. Click **Generate token**
4. Copy the token immediately (only shown once)
5. Store securely in Key Vault or GitHub Secrets

```bash
# Store in Azure Key Vault (recommended)
az keyvault secret set \
  --vault-name <your-keyvault> \
  --name "databricks-scim-token" \
  --value "<paste-token-here>"
```

### Step 3: Configure Enterprise Application Provisioning

Azure Portal steps:

1. Go to **Azure AD** → **Enterprise applications**
2. Find your SCIM app (created by OpenTofu)
3. Click **Provisioning** in left menu
4. Click **Get started**
5. Set **Provisioning Mode** to **Automatic**
6. Under **Admin Credentials**, set:
   - **Tenant URL**: `https://accounts.azuredatabricks.net/api/2.0/accounts/<ACCOUNT_ID>/scim/v2`
   - **Secret Token**: Paste token from Step 2
7. Click **Test Connection** → Should show "Success"
8. Save configuration
9. Under **Mappings**, review/adjust attribute mappings (defaults are usually fine)
10. Under **Settings**, set **Scope** to **Sync only assigned users and groups**
11. Click **Start provisioning**

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `application_name` | Display name for Azure AD SCIM application | `string` | `"Databricks SCIM Provisioning"` | no |
| `databricks_account_id` | Databricks Account ID (for SCIM tenant URL) | `string` | n/a | yes |
| `assigned_groups` | Map of Azure AD groups to assign | `map(object)` | `{}` | no |
| `assigned_users` | Map of Azure AD users to assign | `map(object)` | `{}` | no |
| `tags` | Tags for Azure AD resources | `list(string)` | `["databricks", "scim", "provisioning"]` | no |

## Outputs

| Name | Description |
|------|-------------|
| `application_id` | Application (client) ID of SCIM app |
| `application_object_id` | Object ID of SCIM app registration |
| `service_principal_id` | Object ID of SCIM service principal |
| `scim_tenant_url` | SCIM tenant URL for Databricks |
| `manual_steps_required` | Instructions for manual completion steps |
| `assigned_groups` | Azure AD groups assigned to SCIM |
| `assigned_users` | Azure AD users assigned to SCIM |

## Benefits

### Automation

- App registration via OpenTofu (no manual Azure Portal clicks)
- Group/user assignments managed as code
- Repeatable across environments (dev/prod)

### Security

- API permissions explicitly defined
- Assigned users/groups tracked in code
- SCIM token stored in Key Vault

### Compliance

- All assignments auditable via Git history
- Infrastructure as Code for identity management
- Consistent configuration across environments

## Prerequisites

- Entra ID P1 or P2 license (required for SCIM)
- Databricks Premium or Enterprise (required for SCIM)
- Account Administrator access in Databricks Account Console
- Azure AD Global Administrator or Privileged Role Administrator (for admin consent)

## Limitations

Due to Azure AD/Databricks API limitations:

1. **SCIM token generation**: Must be done via Databricks Account Console UI (no API endpoint)
2. **Enterprise App provisioning**: Gallery App configuration not fully supported by OpenTofu
3. **Attribute mappings**: Default mappings must be reviewed manually (usually fine as-is)

These are quick one-time tasks that take ~5 minutes. The module eliminates dozens of manual clicks.

## Troubleshooting

### "Insufficient privileges to complete the operation"

Grant admin consent for API permissions (see Step 1 above).

### "Invalid SCIM token"

Regenerate token in Account Console. Tokens don't expire but can be invalidated.

### "Provisioning failed: Access denied"

Check that service principal has correct API permissions and admin consent granted.

### Users not syncing

Verify:

1. Users/groups are assigned to Enterprise App
2. Provisioning scope is set to "Sync only assigned users and groups"
3. Provisioning status is "On"

Check provisioning logs:

```bash
# View provisioning logs
az ad app provisioning-job show-logs \
  --service-principal-id <SP_OBJECT_ID>
```

## References

- [Databricks SCIM API Documentation](https://docs.databricks.com/administration-guide/users-groups/scim/aad.html)
- [Azure AD SCIM Provisioning](https://learn.microsoft.com/en-us/azure/active-directory/app-provisioning/user-provisioning)
- [Azure AD Provider Documentation](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs)
