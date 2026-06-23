# Module: databricks-grants

Manages **Unity Catalog permissions** independently from resource creation. Decoupling grants from the `unity-catalog` module allows permission updates without re-applying the full infrastructure stack.

> **Note on Group Names**: As of February 2026, this blueprint uses **environment-specific group names** for strict dev/prod separation:
>
> - Dev: `Databricks-Admins-Dev`, `Databricks-Engineers-Dev`, `Databricks-Analysts-Dev`, etc.
> - Prod: `Databricks-Admins-Prod`, `Databricks-Engineers-Prod`, `Databricks-Analysts-Prod`, etc.
>
> Examples in this README use the dev group names (`*-Dev`). For prod, substitute with `*-Prod` suffix.
> See [Environment Separation Guide](../../../docs/guides/environment-separation.md) for complete strategy.

## Resources

| Resource | Condition |
|----------|-----------|
| `databricks_grants.catalog` | `length(catalog_grants) > 0` |
| `databricks_grants.schemas` | one per entry in `schema_grants` |
| `databricks_grants.external_locations` | one per entry in `external_location_grants` |

## Usage

```hcl
module "databricks_grants" {
  source    = "../../modules/databricks-grants"
  providers = { databricks = databricks.workspace }

  catalog_name = module.unity_catalog.catalog_name

  # Use environment-specific group names (created by AIM module)
  catalog_grants = {
    engineers = { principal = "Databricks-Engineers-Dev", privileges = ["USE_CATALOG", "USE_SCHEMA", "CREATE_TABLE"] }
    analysts  = { principal = "Databricks-Analysts-Dev",  privileges = ["USE_CATALOG", "USE_SCHEMA"] }
  }

  schema_grants = {
    bronze = {
      engineers = { principal = "Databricks-Engineers-Dev", privileges = ["SELECT", "MODIFY"] }
    }
    gold = {
      analysts  = { principal = "Databricks-Analysts-Dev",  privileges = ["SELECT"] }
    }
  }

  external_location_grants = {
    "lakehouse_dev_bronze" = {
      engineers = { principal = "Databricks-Engineers-Dev", privileges = ["READ_FILES", "WRITE_FILES"] }
    }
  }

  depends_on = [module.unity_catalog]
}

# For prod environment, use -Prod suffix:
# catalog_grants = {
#   engineers = { principal = "Databricks-Engineers-Prod", ... }
# }
```

## Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `catalog_name` | `string` | — | Unity Catalog catalog name |
| `catalog_grants` | `map(object({principal, privileges}))` | `{}` | Catalog-level grants |
| `schema_grants` | `map(map(object({principal, privileges})))` | `{}` | Schema-level grants. Outer key = schema name |
| `external_location_grants` | `map(map(object({principal, privileges})))` | `{}` | External location grants. Outer key = external location name |

## Outputs

| Name | Description |
|------|-------------|
| `catalog_grants_applied` | `true` when catalog grants were applied |
| `schema_grants_applied` | Set of schema names with applied grants |
| `external_location_grants_applied` | Set of external location names with applied grants |

## State Migration

If you are extracting grants that previously lived inside the `unity-catalog` module, run `tofu state mv` to avoid destroy+recreate:

```bash
# Example: move catalog grant from unity-catalog module to databricks-grants module
tofu state mv \
  'module.unity_catalog.databricks_grants.catalog[0]' \
  'module.databricks_grants.databricks_grants.catalog[0]'

# Example: move schema-level grant
tofu state mv \
  'module.unity_catalog.databricks_grants.schemas["bronze"]' \
  'module.databricks_grants.databricks_grants.schemas["bronze"]'
```

After the state move, `tofu plan` must show **0 resources to destroy**.

## Complete Access Control Workflow

This module handles **authorization** (what users can access). It works together with the `databricks-aim` module which handles **identity** (who can log in).

### The Complete Picture

```text
┌──────────────────────────────────────────────────────────────────┐
│ 1. Identity Management (databricks-aim module)                  │
│ ──────────────────────────────────────────────────────────────── │
│ • Creates Azure AD groups (Databricks-Engineers, etc.)          │
│ • Syncs groups to Databricks Account                            │
│ • Assigns groups to workspaces                                  │
│ • Users log in via Azure AD SSO                                 │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│ 2. Authorization (databricks-grants module - THIS MODULE)       │
│ ──────────────────────────────────────────────────────────────── │
│ • Grants catalog-level permissions (USE_CATALOG, CREATE_SCHEMA) │
│ • Grants schema-level permissions (SELECT, MODIFY)              │
│ • Grants external location permissions (READ_FILES)             │
│ • Users query data based on their group's permissions           │
└──────────────────────────────────────────────────────────────────┘
```

### User Experience Example

**Jane Doe** is added to `Databricks-Engineers` in Azure AD:

1. **AIM syncs** → Jane can log in to workspace
2. **Grants applied** → Jane inherits group permissions:

   ```sql
   USE CATALOG lakehouse_dev;         -- ✅ Works (USE_CATALOG privilege)
   SELECT * FROM bronze.raw_customers; -- ✅ Works (SELECT privilege)
   INSERT INTO bronze.raw_customers VALUES (...); -- ✅ Works (MODIFY privilege)
   DROP TABLE bronze.raw_customers;   -- ❌ Denied (no DROP privilege)
   ```

---

## Common Permission Patterns

### Pattern 1: Medallion Architecture (Recommended)

Implement the bronze/silver/gold data quality layers with appropriate access control:

```hcl
module "databricks_grants" {
  source       = "../../modules/databricks-grants"
  catalog_name = "lakehouse_dev"

  # Catalog-level: Basic access for all
  catalog_grants = [
    {
      principal  = "Databricks-Admins"
      privileges = ["ALL_PRIVILEGES"]  # Full control
    },
    {
      principal  = "Databricks-Engineers"
      privileges = ["USE_CATALOG", "CREATE_SCHEMA", "USE_SCHEMA"]
    },
    {
      principal  = "Databricks-Analysts"
      privileges = ["USE_CATALOG", "USE_SCHEMA"]  # Read-only at catalog level
    }
  ]

  # Schema-level: Graduated access by layer
  schema_grants = {
    # Bronze: Raw data - Engineers only
    "bronze" = [
      {
        principal  = "Databricks-Engineers"
        privileges = ["SELECT", "MODIFY", "CREATE_TABLE"]
      }
      # Analysts: NO ACCESS to raw data
    ]

    # Silver: Cleaned data - Engineers write, Analysts read
    "silver" = [
      {
        principal  = "Databricks-Engineers"
        privileges = ["SELECT", "MODIFY", "CREATE_TABLE"]
      },
      {
        principal  = "Databricks-Analysts"
        privileges = ["SELECT"]  # Read-only access
      }
    ]

    # Gold: Business-ready - Both can access
    "gold" = [
      {
        principal  = "Databricks-Engineers"
        privileges = ["SELECT", "MODIFY", "CREATE_TABLE"]
      },
      {
        principal  = "Databricks-Analysts"
        privileges = ["SELECT", "CREATE_TABLE"]  # Can create aggregations
      }
    ]
  }
}
```

**Why this pattern?**

- Protects sensitive raw data (bronze) from analysts
- Allows analysts to work with clean data (silver/gold)
- Engineers can write at all layers (for ETL pipelines)
- Follows least-privilege principle

---

### Pattern 2: Role-Based Access Control (RBAC)

```hcl
locals {
  # Define roles with their permissions
  roles = {
    admin = {
      principals = ["Databricks-Admins"]
      privileges = ["ALL_PRIVILEGES"]
    }
    writer = {
      principals = ["Databricks-Engineers", "Databricks-ETL-Service"]
      privileges = ["USE_CATALOG", "USE_SCHEMA", "CREATE_SCHEMA", "CREATE_TABLE", "SELECT", "MODIFY"]
    }
    reader = {
      principals = ["Databricks-Analysts", "Databricks-DataScientists"]
      privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
    }
  }

  # Flatten for catalog grants
  catalog_grants_list = flatten([
    for role_name, role_config in local.roles : [
      for principal in role_config.principals : {
        principal  = principal
        privileges = role_config.privileges
      }
    ]
  ])
}

module "databricks_grants" {
  source         = "../../modules/databricks-grants"
  catalog_name   = "lakehouse_dev"
  catalog_grants = local.catalog_grants_list
}
```

---

### Pattern 3: Environment-Specific Permissions

**Dev**: Permissive (engineers can experiment)

```hcl
# infra/envs/dev/main.tf
module "databricks_grants" {
  source       = "../../modules/databricks-grants"
  catalog_name = "lakehouse_dev"

  schema_grants = {
    "bronze" = [
      {
        principal  = "Databricks-Engineers"
        privileges = ["SELECT", "MODIFY", "CREATE_TABLE", "DROP"]  # Full access
      }
    ]
  }
}
```

**Prod**: Restrictive (only service accounts write)

```hcl
# infra/envs/prod/main.tf
module "databricks_grants" {
  source       = "../../modules/databricks-grants"
  catalog_name = "lakehouse_prod"

  schema_grants = {
    "bronze" = [
      {
        principal  = "Databricks-Engineers"
        privileges = ["SELECT"]  # Read-only for debugging
      },
      {
        principal  = "Databricks-ETL-Service"  # Service principal for automated jobs
        privileges = ["SELECT", "MODIFY", "CREATE_TABLE"]
      }
    ]
  }
}
```

---

### Pattern 4: Data Science Workload

Grant ML engineers access to feature stores and model registries:

```hcl
module "databricks_grants" {
  source       = "../../modules/databricks-grants"
  catalog_name = "lakehouse_dev"

  schema_grants = {
    # Source data: Read-only
    "silver" = [
      {
        principal  = "Databricks-DataScientists"
        privileges = ["SELECT"]
      }
    ]

    # Feature store: Read + write
    "features" = [
      {
        principal  = "Databricks-DataScientists"
        privileges = ["SELECT", "MODIFY", "CREATE_TABLE"]
      }
    ]

    # Model registry: Read + write
    "models" = [
      {
        principal  = "Databricks-DataScientists"
        privileges = ["SELECT", "MODIFY", "CREATE_TABLE", "EXECUTE"]
      }
    ]
  }
}
```

---

## Unity Catalog Privilege Reference

### Catalog-Level Privileges

| Privilege | Allows |
|-----------|--------|
| `USE_CATALOG` | View catalog and list schemas (required for any access) |
| `CREATE_SCHEMA` | Create new schemas |
| `USE_SCHEMA` | Access schemas (required to list tables) |
| `ALL_PRIVILEGES` | Full control (admins only) |

### Schema-Level Privileges

| Privilege | Allows |
|-----------|--------|
| `USE_SCHEMA` | List tables/views in schema |
| `SELECT` | Read data from tables |
| `MODIFY` | Insert/update/delete data |
| `CREATE_TABLE` | Create new tables |
| `CREATE_FUNCTION` | Create functions/UDFs |
| `EXECUTE` | Run functions |
| `ALL_PRIVILEGES` | Full control over schema |

### External Location Privileges

| Privilege | Allows |
|-----------|--------|
| `READ_FILES` | Read files from external storage |
| `WRITE_FILES` | Write files to external storage |
| `CREATE_EXTERNAL_TABLE` | Create external tables |
| `ALL_PRIVILEGES` | Full control over external location |

### Privilege Hierarchy

```text
ALL_PRIVILEGES (includes everything below)
├── CREATE_SCHEMA
├── CREATE_TABLE
├── CREATE_FUNCTION
├── USE_CATALOG / USE_SCHEMA (required for visibility)
├── SELECT (read data)
├── MODIFY (write data)
└── EXECUTE (run functions)
```

**Important**: `USE_CATALOG` and `USE_SCHEMA` are **prerequisites** for most operations. Without them, objects are invisible to users.

---

## Advanced Use Cases

### Row-Level Security via Dynamic Views

```sql
-- Create a function that checks user group membership
CREATE FUNCTION mask_sensitive_columns(
  email STRING,
  ssn STRING
)
RETURNS STRUCT<email: STRING, ssn: STRING>
RETURN 
  CASE 
    WHEN is_member('Databricks-Admins') THEN 
      STRUCT(email, ssn)  -- Full access
    WHEN is_member('Databricks-Engineers') THEN 
      STRUCT(email, 'REDACTED')  -- Partial access
    ELSE 
      STRUCT('REDACTED', 'REDACTED')  -- No PII
  END;

-- Use in a view
CREATE VIEW customers_filtered AS
SELECT 
  customer_id,
  name,
  mask_sensitive_columns(email, ssn).*
FROM customers;

-- Grant access to the view
GRANT SELECT ON VIEW customers_filtered TO `Databricks-Analysts`;
```

**Grant configuration**:

```hcl
schema_grants = {
  "sensitive_data" = [
    {
      principal  = "Databricks-Analysts"
      privileges = ["SELECT"]  # Can only read through filtered view
    },
    {
      principal  = "Databricks-Admins"
      privileges = ["SELECT", "MODIFY"]  # Can access raw table
    }
  ]
}
```

---

### Column-Level Security

```sql
-- Grant access only to specific columns
GRANT SELECT (customer_id, name, city) 
  ON TABLE customers 
  TO `Databricks-Analysts`;
```

**Note**: Column-level grants are not supported in this module (use SQL directly for fine-grained control).

---

### Time-Limited Access

**Scenario**: Grant contractors 90-day access.

```hcl
# infra/envs/dev/main.tf
locals {
  contractor_expiry = "2026-05-25"  # 90 days from deployment
  contractor_active = timecmp(plantimestamp(), "${local.contractor_expiry}T00:00:00Z") < 0

  contractor_grants = local.contractor_active ? [
    {
      principal  = "Databricks-Contractors"
      privileges = ["SELECT"]
    }
  ] : []
}

module "databricks_grants" {
  source       = "../../modules/databricks-grants"
  catalog_name = "lakehouse_dev"

  schema_grants = {
    "gold" = concat(
      var.standard_grants,
      local.contractor_grants  # ← Automatically expires
    )
  }
}
```

**Better approach**: Use Azure AD Privileged Identity Management (PIM) for temporary role assignments.

---

### Multi-Catalog Access

**Scenario**: Give teams access to multiple catalogs with different permissions.

```hcl
# Engineering catalog (full access)
module "grants_engineering" {
  source       = "../../modules/databricks-grants"
  catalog_name = "engineering_lakehouse"

  catalog_grants = [
    {
      principal  = "Databricks-Engineers"
      privileges = ["ALL_PRIVILEGES"]
    }
  ]
}

# Analytics catalog (read-only)
module "grants_analytics" {
  source       = "../../modules/databricks-grants"
  catalog_name = "analytics_lakehouse"

  catalog_grants = [
    {
      principal  = "Databricks-Analysts"
      privileges = ["USE_CATALOG", "USE_SCHEMA"]
    }
  ]

  schema_grants = {
    "dashboards" = [
      {
        principal  = "Databricks-Analysts"
        privileges = ["SELECT", "CREATE_TABLE"]  # Can build dashboards
      }
    ]
  }
}
```

---

## Configuration Best Practices

### 1. Module Variables Should Be Passed from Environment Files

**✅ Correct (DRY principle)**:

```hcl
# infra/envs/dev/main.tf
module "databricks_grants" {
  source       = "../../modules/databricks-grants"
  catalog_name = var.catalog_name  # ← From dev.tfvars

  catalog_grants = var.catalog_grants  # ← From dev.tfvars
  schema_grants  = var.schema_grants   # ← From dev.tfvars
}
```

```hcl
# infra/envs/dev.tfvars (committed, customer-specific)
catalog_name = "acme_corp_lakehouse_dev"

catalog_grants = [
  {
    principal  = "Databricks-Acme-Engineers"
    privileges = ["USE_CATALOG", "CREATE_SCHEMA"]
  }
]

schema_grants = {
  "bronze" = [
    {
      principal  = "Databricks-Acme-Engineers"
      privileges = ["SELECT", "MODIFY"]
    }
  ]
}
```

**❌ Wrong (hardcoding in module)**:

```hcl
# DON'T DO THIS - Never edit infra/modules/databricks-grants/main.tf
resource "databricks_grants" "catalog" {
  catalog = "my_company_catalog"  # ❌ Hardcoded
  
  grant {
    principal  = "My-Company-Team"  # ❌ Not reusable
    privileges = ["SELECT"]
  }
}
```

**Why?** Modules should be generic and reusable. Customer-specific configuration belongs in environment files.

---

### 2. Use Locals for Complex Logic

```hcl
# infra/envs/dev/main.tf
locals {
  # Standard roles
  admin_groups = ["Databricks-Admins"]
  writer_groups = ["Databricks-Engineers", "Databricks-ETL-Service"]
  reader_groups = ["Databricks-Analysts", "Databricks-DataScientists"]

  # Generate catalog grants from roles
  catalog_grants = concat(
    [for group in local.admin_groups : {
      principal  = group
      privileges = ["ALL_PRIVILEGES"]
    }],
    [for group in local.writer_groups : {
      principal  = group
      privileges = ["USE_CATALOG", "CREATE_SCHEMA", "USE_SCHEMA", "SELECT", "MODIFY"]
    }],
    [for group in local.reader_groups : {
      principal  = group
      privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
    }]
  )
}

module "databricks_grants" {
  source         = "../../modules/databricks-grants"
  catalog_name   = var.catalog_name
  catalog_grants = local.catalog_grants
}
```

---

### 3. Document Custom Permissions

```hcl
# infra/envs/prod/main.tf
module "databricks_grants" {
  source       = "../../modules/databricks-grants"
  catalog_name = "lakehouse_prod"

  schema_grants = {
    "bronze" = [
      {
        principal  = "Databricks-ETL-Service"
        privileges = ["SELECT", "MODIFY", "CREATE_TABLE"]
        # Justification: Automated ETL pipelines need write access to bronze layer
      },
      {
        principal  = "Databricks-Engineers"
        privileges = ["SELECT"]
        # Justification: Production debugging only, no writes allowed
      }
    ]
  }
}
```

---

## Troubleshooting

### Issue: User Can't See Catalog

**Symptom**: `CATALOG_DOES_NOT_EXIST` error when running queries.

**Cause**: User's group doesn't have `USE_CATALOG` privilege.

**Fix**:

```hcl
catalog_grants = [
  {
    principal  = "Databricks-Engineers"  # ← Ensure this matches the user's group
    privileges = ["USE_CATALOG"]  # ← Required to see the catalog
  }
]
```

**Verify**:

```sql
SHOW CATALOGS;  -- Should list lakehouse_dev
```

---

### Issue: User Can't List Tables

**Symptom**: Catalog is visible but `SHOW TABLES` returns empty.

**Cause**: Missing `USE_SCHEMA` privilege.

**Fix**:

```hcl
catalog_grants = [
  {
    principal  = "Databricks-Engineers"
    privileges = ["USE_CATALOG", "USE_SCHEMA"]  # ← Both required
  }
]
```

---

### Issue: `PERMISSION_DENIED` on SELECT

**Symptom**: Can see tables but can't query them.

**Cause**: Missing schema-level `SELECT` privilege.

**Fix**:

```hcl
schema_grants = {
  "bronze" = [
    {
      principal  = "Databricks-Engineers"
      privileges = ["SELECT"]  # ← Add this
    }
  ]
}
```

---

### Issue: Grants Not Applied After `tofu apply`

**Cause**: `depends_on` missing, grants applied before catalog exists.

**Fix**:

```hcl
module "databricks_grants" {
  source       = "../../modules/databricks-grants"
  catalog_name = module.unity_catalog.catalog_name

  catalog_grants = [...]

  depends_on = [module.unity_catalog]  # ← Ensure catalog exists first
}
```

---

### Issue: Multiple Grants Conflict

**Symptom**: Plan shows destroy+recreate of grants on every apply.

**Cause**: `databricks_grants` is **authoritative** — managing the same object in multiple places causes conflicts.

**Fix**: Consolidate all grants for a catalog/schema in ONE module invocation:

**❌ Wrong (causes conflicts)**:

```hcl
module "grants_engineers" {
  source       = "../../modules/databricks-grants"
  catalog_name = "lakehouse_dev"
  catalog_grants = [{ principal = "Databricks-Engineers", ... }]
}

module "grants_analysts" {
  source       = "../../modules/databricks-grants"
  catalog_name = "lakehouse_dev"  # ← Same catalog!
  catalog_grants = [{ principal = "Databricks-Analysts", ... }]
}
```

**✅ Correct (single source of truth)**:

```hcl
module "databricks_grants" {
  source       = "../../modules/databricks-grants"
  catalog_name = "lakehouse_dev"

  catalog_grants = [
    { principal = "Databricks-Engineers", ... },
    { principal = "Databricks-Analysts", ... }
  ]
}
```

---

## Checking Applied Permissions

### Via SQL

```sql
-- Show all grants on catalog
SHOW GRANTS ON CATALOG lakehouse_dev;

-- Show grants on specific schema
SHOW GRANTS ON SCHEMA lakehouse_dev.bronze;

-- Check current user's effective permissions
SHOW GRANTS ON CATALOG lakehouse_dev FOR `current_user()`;
```

### Via Databricks CLI

```bash
# List catalog grants
databricks grants get --catalog lakehouse_dev

# List schema grants
databricks grants get --schema lakehouse_dev.bronze
```

### Via Unity Catalog Explorer (GUI)

```text
1. Open Databricks Workspace
2. Click "Data" in left sidebar
3. Navigate to catalog → schema
4. Click "Permissions" tab
5. View all granted principals and their privileges
```

---

## Notes

- All three resources use `databricks_grants` which is an **authoritative** resource — it replaces all existing grants on the target object. Do not manage grants for the same object in multiple places.
- This module requires the workspace-level Databricks provider.
- `external_location_grants` uses the external location's full name (e.g. `lakehouse_dev_bronze`), not the ABFSS URL.
- **Module is generic**: Pass all customer-specific configuration via variables from environment files (`infra/envs/{dev,prod}/main.tf` or `.tfvars`).
