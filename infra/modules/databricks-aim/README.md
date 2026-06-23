# Databricks Account Identity Management (AIM) Module

Native Azure AD identity sync for Databricks workspaces. The modern, recommended approach for user and group management.

> **Note**: As of February 2026, this blueprint uses **environment-specific group names** (e.g., `Databricks-Admins-Dev` / `Databricks-Admins-Prod`) for strict dev/prod separation.
> See [Environment Separation Guide](../../../docs/guides/environment-separation.md) for the complete strategy.

## Overview

**Account Identity Management (AIM)** is the successor to SCIM provisioning. It provides seamless Azure AD integration for Databricks without the complexity of Enterprise Applications or Gallery Apps.

### Why AIM over SCIM?

| Feature | AIM (Recommended) | SCIM (Legacy) |
|---------|-------------------|---------------|
| **Setup Complexity** | ✅ Fully automated via OpenTofu | ⚠️ 3 manual steps required |
| **Azure AD License** | ✅ Free tier sufficient | ❌ Requires Premium P1/P2 |
| **Enterprise App** | ✅ Not needed | ❌ Required (Gallery App) |
| **Token Management** | ✅ No tokens | ❌ Token rotation needed |
| **Admin Consent** | ✅ Not required | ⚠️ Required |
| **Federation Type** | ✅ Native Azure AD | ⚠️ SCIM 2.0 protocol |
| **Sync Speed** | ✅ Near real-time (< 5 min) | ⚠️ Eventual (15-40 min) |
| **Databricks Tier** | ✅ Premium or Enterprise | ❌ Premium or Enterprise |
| **Account ID Required** | ✅ Yes | ❌ Yes |

### What This Module Does

- ✅ Creates Azure AD security groups (or references existing ones)
- ✅ Syncs groups to Databricks Account level
- ✅ Assigns groups to workspaces with permissions
- ✅ Manages direct user assignments (optional)
- ✅ Configures workspace-level group memberships
- ✅ **100% automated** - no manual steps required (with proper permissions)

---

## Group Creation Modes

This module supports two modes for managing Azure AD groups:

### Mode 1: Automatic Creation (Recommended) ✅

**When to use**: CI/CD service principal has `Group.ReadWrite.All` permission

```hcl
module "databricks_aim" {
  source = "../../modules/databricks-aim"
  
  # Enable automatic group creation
  create_azure_groups = true  # Default: false
  
  groups = {
    admins = {
      display_name  = "Databricks-Admins-Dev"
      mail_nickname = "databricks-admins-dev"
      # ...
    }
  }
}
```

**Benefits**:

- ✅ Fully automated - no manual steps
- ✅ Groups created as part of infrastructure deployment  
- ✅ Ideal for GitOps workflows
- ✅ Scales to multiple environments/projects

**Requirements**:

- Azure AD API permission: `Group.ReadWrite.All`
- See [CI/CD Permissions Guide](../../../docs/guides/cicd-permissions.md) for setup

### Mode 2: Reference Existing Groups (Current Default) 🔄

**When to use**: CI/CD lacks elevated permissions or security policy requires pre-created groups

```hcl
module "databricks_aim" {
  source = "../../modules/databricks-aim"
  
  # Use existing groups (default)
  create_azure_groups = false  # or omit (default: false)
  
  groups = {
    admins = {
      display_name  = "Databricks-Admins-Dev"  # Must exist in Azure AD
      mail_nickname = "databricks-admins-dev"  # Not used (for documentation)
      # ...
    }
  }
}
```

**Benefits**:

- ✅ No elevated Azure AD permissions required
- ✅ Groups can be pre-approved by IT/security team
- ✅ Safer for highly regulated environments

**Requirements**:

- Groups must be created manually first using:
  - Azure Portal → Azure AD → Groups
  - Azure CLI: `az ad group create --display-name "..." --mail-nickname "..."`
  - Script: `./scripts/create-azure-groups.sh dev`

**Trade-off**: Requires one-time manual group creation per environment

---

## Which Mode Should I Use?

| Scenario | Recommended Mode | Reason |
|----------|------------------|--------|
| **Standard deployment** | ✅ Automatic (`create_azure_groups = true`) | Full automation, best GitOps experience |
| **CI/CD lacks permissions** | 🔄 Existing groups (`create_azure_groups = false`) | Temporary workaround until permissions granted |
| **High security requirements** | 🔄 Existing groups | IT/security pre-approves all groups |
| **POC / Demo** | ✅ Automatic | Fastest setup |
| **Enterprise production** | ✅ Automatic + approval gates | Automation with governance |

**Recommendation**: Grant `Group.ReadWrite.All` to your CI/CD service principal for the best experience.  
See [CI/CD Permissions Guide](../../../docs/guides/cicd-permissions.md) for setup instructions.

---

## Architecture

```text
Azure AD Groups              Databricks Account           Databricks Workspaces
┌──────────────────┐        ┌─────────────────┐         ┌──────────────────┐
│ Databricks-Admins│───────>│ Account Groups  │────────>│ Workspace Admin  │
│ Databricks-Users │        │ (AIM Federated) │         │ Workspace User   │
│ Databricks-Engineers│      │                 │         │                  │
│ Databricks-Analysts│       └─────────────────┘         └──────────────────┘
└──────────────────┘
        │
        └─> Add users via Azure AD Portal
            Automatic sync to Databricks (< 5 min)
```

## Usage

### Basic Setup (Recommended)

```hcl
# Fetch Databricks workspace details
data "databricks_current_user" "me" {
  provider = databricks.workspace
}

# Configure AIM with environment-specific groups
module "databricks_aim" {
  source = "../../modules/databricks-aim"

  providers = {
    databricks.account   = databricks.account
    databricks.workspace = databricks.workspace
  }

  # Define Azure AD groups to create and sync
  # Use environment-specific names (e.g., add "-Dev" or "-Prod" suffix)
  groups = {
    admins = {
      display_name               = "Databricks-Admins-Dev"  # or -Prod
      description                = "Databricks workspace administrators for dev environment"
      mail_nickname              = "databricks-admins-dev"
      allow_cluster_create       = true
      allow_instance_pool_create = true
    }
    engineers = {
      display_name               = "Databricks-Engineers-Dev"  # or -Prod
      description                = "Data Engineers with write access to dev"
      mail_nickname              = "databricks-engineers-dev"
      allow_cluster_create       = true  # Set to false in prod
      allow_instance_pool_create = false
    }
    analysts = {
      display_name               = "Databricks-Analysts"
      description                = "Data Analysts with read-only access"
      mail_nickname              = "databricks-analysts"
      allow_cluster_create       = false
      allow_instance_pool_create = false
    }
    users = {
      display_name               = "Databricks-Users"
      description                = "Standard users with limited access"
      mail_nickname              = "databricks-users"
      allow_cluster_create       = false
      allow_instance_pool_create = false
    }
  }

  # Assign groups to workspace
  workspace_assignments = {
    admins_dev = {
      workspace_id = var.workspace_id
      group_key    = "admins"
      permissions  = ["ADMIN"]
    }
    engineers_dev = {
      workspace_id = var.workspace_id
      group_key    = "engineers"
      permissions  = ["USER"]
    }
    analysts_dev = {
      workspace_id = var.workspace_id
      group_key    = "analysts"
      permissions  = ["USER"]
    }
  }

  tags = ["dev", "databricks", "aim"]
}

# Output setup instructions
output "aim_setup_complete" {
  value = module.databricks_aim.next_steps
}
```

### Advanced: Direct User Assignment

Use only when group-based access is insufficient:

```hcl
# Fetch specific users from Azure AD
data "azuread_user" "admin" {
  user_principal_name = "admin@company.com"
}

module "databricks_aim" {
  source = "../../modules/databricks-aim"

  providers = {
    databricks.account   = databricks.account
    databricks.workspace = databricks.workspace
  }

  # Groups (as above)
  groups = { ... }

  # Direct user assignments
  direct_users = {
    admin = {
      user_principal_name = data.azuread_user.admin.user_principal_name
      display_name        = data.azuread_user.admin.display_name
      object_id           = data.azuread_user.admin.object_id
    }
  }
}
```

### Advanced: Workspace-Level Group Assignments

Assign account groups to specific workspace groups (e.g., `admins` built-in group):

```hcl
# Get workspace built-in groups
data "databricks_group" "workspace_admins" {
  provider     = databricks.workspace
  display_name = "admins"
}

module "databricks_aim" {
  source = "../../modules/databricks-aim"

  providers = {
    databricks.account   = databricks.account
    databricks.workspace = databricks.workspace
  }

  groups = { ... }

  # Assign account groups to workspace groups
  workspace_group_assignments = {
    dev_workspace = {
      workspace_id = var.workspace_id
      groups = {
        admins = {
          workspace_group    = "admins"
          workspace_group_id = data.databricks_group.workspace_admins.id
        }
      }
    }
  }
}
```

## Post-Deployment Steps

After `tofu apply` completes:

### 1. Add Users to Azure AD Groups

```bash
# Via Azure CLI
az ad group member add \
  --group "Databricks-Engineers" \
  --member-id <user-object-id>

# Or via Azure Portal
# Azure Portal → Azure Active Directory → Groups → [Select Group] → Members → Add
```

### 2. Verify Sync (Automatic)

Users appear in Databricks within **5 minutes**:

```bash
# Check Databricks Account Console
# https://accounts.azuredatabricks.net → User Management → Groups

# Or via Databricks CLI
databricks account groups list --account-id <account-id>
```

### 3. No Further Configuration Required! ✅

AIM handles all identity federation automatically. Users inherit permissions from their Azure AD group memberships.

## Troubleshooting

### Users Not Appearing in Databricks

**Wait 5-10 minutes** - AIM sync is near real-time but may have slight delays.

Verify Azure AD group membership:

```bash
az ad group member list --group "Databricks-Engineers" --output table
```

Check Databricks Account Console:

```text
https://accounts.azuredatabricks.net → User Management → Groups
```

### Permission Denied Errors

Ensure the OpenTofu execution principal has:

- **Azure AD**: `Global Administrator` or `Privileged Role Administrator`
- **Databricks**: Account admin via Account Console

### Group Already Exists

If Azure AD groups exist, import them instead:

```bash
tofu import 'module.databricks_aim.azuread_group.databricks_groups["admins"]' <group-object-id>
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `groups` | Azure AD groups to create and sync | `map(object)` | `{}` | no |
| `workspace_assignments` | Assign groups to workspaces | `map(object)` | `{}` | no |
| `direct_users` | Individual user assignments | `map(object)` | `{}` | no |
| `workspace_group_assignments` | Workspace-level group mappings | `map(object)` | `{}` | no |
| `tags` | Tags for Azure resources | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| `azure_ad_groups` | Created Azure AD groups |
| `databricks_account_groups` | Synced Databricks account groups |
| `workspace_assignments` | Group-to-workspace assignments |
| `databricks_account_users` | Direct user assignments |
| `setup_summary` | Configuration summary |
| `next_steps` | Post-deployment instructions |

## Requirements

| Name | Version |
|------|---------|
| opentofu | >= 1.10.0 |
| azuread | ~> 2.47 |
| databricks | ~> 1.70 |

## Providers

| Name | Alias | Configuration |
|------|-------|---------------|
| azuread | - | Default Azure AD provider |
| databricks | account | Account-level operations |
| databricks | workspace | Workspace-level operations |

## Resources Created

### Azure Resources

- `azuread_group.databricks_groups` - Security groups for Databricks access

### Databricks Resources

- `databricks_group.account_groups` - Account-level groups (AIM federated)
- `databricks_mws_permission_assignment.workspace_access` - Workspace access grants
- `databricks_user.account_users` - Direct user accounts (optional)
- `databricks_group_member.workspace_group_members` - Workspace group mapperships

## Best Practices

### 1. Use Groups Over Direct Users

Always prefer group-based access for scalability:

✅ **Good**: Assign `Databricks-Engineers` group to workspace
❌ **Bad**: Assign individual users one-by-one

### 2. Follow Principle of Least Privilege

```hcl
# Admins: Full access
allow_cluster_create = true

# Engineers: Create clusters, no pools
allow_cluster_create       = true
allow_instance_pool_create = false

# Analysts: Read-only
allow_cluster_create       = false
allow_instance_pool_create = false
```

### 3. Use Consistent Naming

```text
Databricks-<Role>
  ├── Databricks-Admins
  ├── Databricks-Engineers
  ├── Databricks-Analysts
  └── Databricks-Users
```

### 4. Tag Everything

```hcl
tags = ["environment:dev", "team:data", "cost-center:engineering"]
```

### 5. Separate Dev and Prod

Create separate group sets per environment:

```text
Databricks-Dev-Engineers
Databricks-Prod-Engineers
```

## Migration from SCIM

Migrating from SCIM to AIM? Follow these steps:

### 1. Document Existing Groups

```bash
# List current SCIM groups
databricks account groups list --account-id <account-id>
```

### 2. Remove SCIM Module

```hcl
# Comment out old SCIM module
# module "databricks_scim" { ... }
```

### 3. Deploy AIM Module

```bash
tofu apply
```

### 4. Verify User Access

Test that users can still access workspaces.

### 5. Clean Up SCIM Resources

- Remove SCIM Enterprise Application from Azure AD
- Delete old SCIM tokens from Databricks Account Console

## Security Considerations

### Identity Federation

AIM uses **Azure AD as the source of truth**:

- Users are authenticated via Azure AD SSO
- Group memberships are managed in Azure AD
- Databricks reads permissions from Azure AD

### Least Privilege

Grant minimal permissions required:

- Most users: `allow_cluster_create = false`
- Engineers: `allow_cluster_create = true`
- Admins only: Full workspace admin permissions

### Audit Trail

All identity changes are logged:

- Azure AD audit logs: Group membership changes
- Databricks system tables: User activity and permissions

## Support Matrix

| Databricks Tier | AIM Support |
|-----------------|-------------|
| Community | ❌ Not supported |
| Standard | ❌ Not supported |
| Premium | ✅ Supported |
| Enterprise | ✅ Supported |

| Azure AD Tier | AIM Support |
|---------------|-------------|
| Free | ✅ Supported |
| Premium P1 | ✅ Supported |
| Premium P2 | ✅ Supported |

## How AIM Works Internally

### Identity Sync Process

```text
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: Azure AD Group Management                               │
│ ─────────────────────────────────────────────────────────────── │
│ 1. OpenTofu creates Azure AD groups (if not exists)             │
│ 2. You add users to groups via Azure Portal/CLI/Terraform       │
│ 3. Azure AD becomes the source of truth for group membership    │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: AIM Federation                                          │
│ ─────────────────────────────────────────────────────────────── │
│ 1. Databricks reads Azure AD group memberships                  │
│ 2. Creates matching Databricks Account Groups                   │
│ 3. Syncs user memberships (5-10 minute interval)                │
│ 4. No SCIM tokens or Enterprise Apps needed                     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: Workspace Assignment                                    │
│ ─────────────────────────────────────────────────────────────── │
│ 1. Groups are assigned to specific workspaces                   │
│ 2. Permissions (ADMIN/USER) are set per workspace               │
│ 3. Users inherit workspace access from group membership         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 4: Unity Catalog Grants (via databricks-grants module)    │
│ ─────────────────────────────────────────────────────────────── │
│ 1. Groups receive catalog/schema/table permissions              │
│ 2. Users can access data based on their group membership        │
│ 3. Permissions are managed independently from identity sync     │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

1. **Azure AD Groups**: `Databricks-Admins`, `Databricks-Engineers`, etc.
2. **Databricks Account Groups**: Synced copies at the account level
3. **Workspace Assignments**: Which groups can access which workspaces
4. **Unity Catalog Grants**: What data each group can access (managed separately)

---

## User Lifecycle Management

### Adding a New User

**Scenario**: Grant Jane Doe engineer access to the dev workspace.

#### Method 1: Azure Portal (GUI)

```text
1. Navigate to: Azure Portal → Azure Active Directory → Groups
2. Select: Databricks-Engineers
3. Click: Members → Add members
4. Search: jane.doe@company.com
5. Click: Select
```

**Result**: Jane can log in to the Databricks workspace within 5-10 minutes and inherits all `Databricks-Engineers` permissions.

#### Method 2: Azure CLI (Automation)

```bash
# Find user object ID
USER_ID=$(az ad user show \
  --id jane.doe@company.com \
  --query id -o tsv)

# Add to group
az ad group member add \
  --group "Databricks-Engineers" \
  --member-id $USER_ID

# Verify membership
az ad group member list \
  --group "Databricks-Engineers" \
  --query "[?displayName=='Jane Doe']"
```

#### Method 3: OpenTofu (Infrastructure as Code)

```hcl
# infra/envs/dev/main.tf

# Fetch user from Azure AD
data "azuread_user" "jane" {
  user_principal_name = "jane.doe@company.com"
}

# Fetch group
data "azuread_group" "engineers" {
  display_name = "Databricks-Engineers"
}

# Add user to group
resource "azuread_group_member" "jane_engineer" {
  group_object_id  = data.azuread_group.engineers.id
  member_object_id = data.azuread_user.jane.id
}
```

```bash
./scripts/tofu-wrapper.sh dev apply
```

---

### Removing User Access

**Scenario**: Revoke access when Jane leaves the team.

#### Via Azure Portal

```text
1. Azure Portal → Azure Active Directory → Groups → Databricks-Engineers
2. Members → Select Jane Doe → Remove
```

#### Via Azure CLI

```bash
USER_ID=$(az ad user show --id jane.doe@company.com --query id -o tsv)
az ad group member remove --group "Databricks-Engineers" --member-id $USER_ID
```

**Result**: Within 5-10 minutes:

- Jane loses workspace access
- Jane loses all Unity Catalog permissions granted to `Databricks-Engineers`
- Jane cannot create clusters or access data
- **No OpenTofu changes required** — AIM handles it automatically

---

### Promoting a User (Role Change)

**Scenario**: Promote Jane from analyst to engineer.

```bash
# Add to new group
az ad group member add \
  --group "Databricks-Engineers" \
  --member-id $USER_ID

# Remove from old group
az ad group member remove \
  --group "Databricks-Analysts" \
  --member-id $USER_ID
```

**Result**: Jane inherits new permissions automatically:

- Can now create clusters (if `allow_cluster_create = true`)
- Gains write access to bronze/silver schemas (if configured in grants module)
- Loses any analyst-only permissions

---

## Access Control Integration

AIM handles **identity** (who can log in). The `databricks-grants` module handles **authorization** (what they can access).

### Complete Access Control Flow

```text
Azure AD Group Membership
        ↓
   [AIM Module Syncs]
        ↓
Databricks Group Membership
        ↓
   [Grants Module Applied]
        ↓
Unity Catalog Permissions
        ↓
   [User Queries Data]
        ↓
Success (if authorized) / Error (if denied)
```

### Example: Engineer Data Access

#### 1. AIM Configuration (Identity)

```hcl
# infra/envs/dev/main.tf
module "databricks_aim" {
  source = "../../modules/databricks-aim"
  
  groups = {
    engineers = {
      display_name         = "Databricks-Engineers"
      allow_cluster_create = true  # ← Controls compute access
    }
  }
  
  workspace_assignments = {
    engineers_dev = {
      workspace_id = var.workspace_id
      group_key    = "engineers"
      permissions  = ["USER"]  # ← Controls workspace login
    }
  }
}
```

#### 2. Grants Configuration (Authorization)

```hcl
# infra/envs/dev/main.tf
module "databricks_grants" {
  source = "../../modules/databricks-grants"
  
  catalog_name = "lakehouse_dev"
  
  catalog_grants = [
    {
      principal  = "Databricks-Engineers"  # ← Must match AIM group name
      privileges = ["USE_CATALOG", "CREATE_SCHEMA"]
    }
  ]
  
  schema_grants = {
    "bronze" = [
      {
        principal  = "Databricks-Engineers"
        privileges = ["SELECT", "MODIFY"]  # ← Read + write access
      }
    ]
  }
}
```

#### 3. User Experience

```sql
-- Jane (in Databricks-Engineers group) can:

USE CATALOG lakehouse_dev;  -- ✅ Works (USE_CATALOG privilege)
USE SCHEMA bronze;          -- ✅ Works (inherited from catalog)

SELECT * FROM raw_customers;  -- ✅ Works (SELECT privilege)
INSERT INTO raw_customers VALUES (...);  -- ✅ Works (MODIFY privilege)

-- Jane cannot:
DROP CATALOG lakehouse_dev;  -- ❌ Denied (no ALL_PRIVILEGES)
```

### Separation of Concerns

| Module | Responsibility | Configuration Scope |
|--------|----------------|---------------------|
| **databricks-aim** | Who can log in | Azure AD groups, workspace access |
| **databricks-grants** | What they can access | Catalog/schema/table permissions |
| **databricks-governance** | What policies apply | Cluster policies, token management |

**Why separate?** Change permissions without affecting identity sync, and vice versa.

---

## Advanced Scenarios

### Multi-Environment Access

**Problem**: Give engineers access to both dev and prod, but different permissions.

```hcl
# infra/envs/dev/main.tf
module "grants_dev" {
  source       = "../../modules/databricks-grants"
  catalog_name = "lakehouse_dev"
  
  schema_grants = {
    "bronze" = [
      {
        principal  = "Databricks-Engineers"
        privileges = ["SELECT", "MODIFY"]  # Full access in dev
      }
    ]
  }
}

# infra/envs/prod/main.tf
module "grants_prod" {
  source       = "../../modules/databricks-grants"
  catalog_name = "lakehouse_prod"
  
  schema_grants = {
    "bronze" = [
      {
        principal  = "Databricks-Engineers"
        privileges = ["SELECT"]  # Read-only in prod
      }
    ]
  }
}
```

### Temporary Contractor Access

**Problem**: Grant 90-day access to external contractors.

```hcl
# infra/envs/dev/main.tf
locals {
  contractor_access_expires = timeadd(timestamp(), "2160h")  # 90 days
  grant_contractor_access   = timecmp(timestamp(), local.contractor_access_expires) < 0
}

module "databricks_aim" {
  source = "../../modules/databricks-aim"
  
  groups = merge(
    var.standard_groups,
    local.grant_contractor_access ? {
      contractors = {
        display_name         = "Databricks-Contractors"
        allow_cluster_create = false
      }
    } : {}
  )
}
```

**Better approach**: Use Azure AD dynamic groups with expiration dates.

### Regional Data Access

**Problem**: EMEA engineers should only access EMEA data.

```hcl
module "databricks_aim" {
  source = "../../modules/databricks-aim"
  
  groups = {
    engineers_emea = {
      display_name         = "Databricks-Engineers-EMEA"
      allow_cluster_create = true
    }
    engineers_apac = {
      display_name         = "Databricks-Engineers-APAC"
      allow_cluster_create = true
    }
  }
}

module "databricks_grants" {
  source = "../../modules/databricks-grants"
  
  schema_grants = {
    "emea_sales" = [
      {
        principal  = "Databricks-Engineers-EMEA"
        privileges = ["SELECT", "MODIFY"]
      }
    ],
    "apac_sales" = [
      {
        principal  = "Databricks-Engineers-APAC"
        privileges = ["SELECT", "MODIFY"]
      }
    ]
  }
}
```

---

## Troubleshooting: Advanced Scenarios

### Users Not Appearing in Databricks

**Symptom**: Added user to Azure AD group but they can't log in.

**Diagnosis Steps**:

1. **Verify Azure AD membership** (should show immediately):

```bash
az ad group member list \
  --group "Databricks-Engineers" \
  --query "[?userPrincipalName=='jane.doe@company.com']"
```

1. **Wait for AIM sync** (5-10 minutes):

```bash
# Check Databricks Account Console
# https://accounts.azuredatabricks.net → User Management → Groups
```

1. **Verify workspace assignment**:

```bash
# Check if group is assigned to workspace
databricks account workspace-assignment list \
  --workspace-id <workspace-id> \
  --account-id <account-id>
```

1. **Check user can authenticate**:

```text
User tries to log in at: https://adb-<workspace-id>.azuredatabricks.net
Should be redirected to Azure AD SSO login
If not, check workspace SAML/SSO configuration
```

**Common Causes**:

- ❌ User added to wrong group (check spelling)
- ❌ Group not assigned to workspace (check `workspace_assignments` in AIM module)
- ❌ Sync hasn't completed yet (wait 10 minutes)
- ❌ User's Azure AD account is disabled (check user status)

---

### Permission Denied Errors

**Symptom**: User can log in but gets "Permission denied" when querying data.

**This is NOT an AIM issue** — AIM only handles identity. Check the `databricks-grants` module:

```bash
# Verify grants for the user's group
databricks grants get --catalog lakehouse_dev

# Expected output should show group with appropriate privileges
```

**Fix**: Add missing grants in `infra/envs/dev/main.tf`:

```hcl
module "databricks_grants" {
  catalog_grants = [
    {
      principal  = "Databricks-Engineers"  # ← Ensure this matches the AIM group name
      privileges = ["USE_CATALOG", "USE_SCHEMA"]
    }
  ]
}
```

---

### Group Already Exists Error

**Symptom**: `tofu apply` fails with "Group already exists in Azure AD".

**Cause**: Group was manually created or exists from previous deployment.

**Fix**: Import existing group into OpenTofu state:

```bash
# Get group object ID
GROUP_ID=$(az ad group show --group "Databricks-Engineers" --query id -o tsv)

# Import into OpenTofu
tofu import 'module.databricks_aim.azuread_group.databricks_groups["engineers"]' $GROUP_ID

# Re-run apply
tofu apply
```

---

### Sync is Slow (> 10 minutes)

**Expected**: AIM typically syncs within 5-10 minutes.

**If longer**:

1. Check Azure AD service health
2. Check Databricks account status page
3. Try manual sync trigger (Databricks Account Console → User Management → Sync Now)

---

## References

- [Databricks Account Identity Management](https://docs.databricks.com/administration-guide/users-groups/best-practices.html)
- [Azure AD Integration](https://learn.microsoft.com/en-us/azure/databricks/administration-guide/users-groups/scim/)
- [OpenTofu Databricks Provider](https://registry.terraform.io/providers/databricks/databricks/latest/docs)
- [Unity Catalog Permissions](https://docs.databricks.com/data-governance/unity-catalog/manage-privileges/index.html)

## License

See [LICENSE](../../../LICENSE) in repository root.
