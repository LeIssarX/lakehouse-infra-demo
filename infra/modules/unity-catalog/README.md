# Unity Catalog Module

This module sets up Databricks Unity Catalog with modern best practices for data governance and access control.

## Features

- **Metastore** creation and workspace assignment
- **Storage credentials** using Azure Managed Identity (Access Connector)
- **External locations** for ADLS Gen2 storage
- **Catalogs** with isolation modes
- **Schemas** for lakehouse layers (bronze/silver/gold)
- **Volumes** (managed and external) for unstructured data
- **Grants** with fine-grained permissions (RBAC)
- **System tables** enablement for lineage and audit
- **Delta Sharing** configuration (optional)

## Modern Unity Catalog Features

### ✅ Volumes (NEW)

- Store unstructured data (PDFs, images, models) alongside tables
- Managed volumes (UC-managed storage)
- External volumes (your ADLS containers)

### ✅ Lakeflow Support

- Optimized catalog structure for **Lakeflow Pipelines**
- **Lakeflow Connect** external location patterns
- Streaming and batch data patterns

### ✅ System Tables

- **Audit logs** - Query who accessed what
- **Lineage** - Track data dependencies
- **Billing** - Cost attribution
- **Predictive optimization** metrics

## Architecture

```text
Unity Catalog Hierarchy:
├── Metastore (account-level)
│   ├── Workspace Assignment
│   ├── Storage Credential (Managed Identity)
│   └── External Locations
│       ├── bronze-storage
│       ├── silver-storage
│       └── gold-storage
└── Catalog (workspace/environment)
    ├── bronze schema
    │   ├── Tables (Delta)
    │   └── Volumes (raw files)
    ├── silver schema
    │   ├── Tables (Delta)
    │   └── Volumes (intermediate files)
    └── gold schema
        ├── Tables (Delta)
        └── Volumes (analytical artifacts)
```

## Resources Created

- `databricks_metastore` - Unity Catalog metastore
- `databricks_metastore_assignment` - Assign metastore to workspace
- `databricks_storage_credential` - Managed identity credential
- `databricks_external_location` - ADLS external locations
- `databricks_catalog` - Catalogs for data organization
- `databricks_schema` - Schemas for lakehouse layers
- `databricks_volume` (optional) - Volumes for files
- `databricks_grants` - Permission grants

## Usage

### Basic Setup (Single Environment)

```hcl
module "unity_catalog" {
  source = "../../modules/unity-catalog"

  # Workspace connection
  workspace_id  = module.databricks_workspace.workspace_id
  workspace_url = module.databricks_workspace.workspace_url
  
  # Metastore
  metastore_name     = "metastore-${var.region}"
  storage_root       = module.storage.metastore_url
  
  # Storage credential (managed identity)
  access_connector_id = module.databricks_workspace.access_connector_id
  
  # Catalog configuration
  catalog_name = "lakehouse_${var.environment}"
  
  # External locations (data layers)
  external_locations = {
    bronze = module.storage.bronze_url
    silver = module.storage.silver_url
    gold   = module.storage.gold_url
  }
  
  # Schemas (lakehouse layers)
  schemas = {
    bronze = {
      comment = "Raw ingested data (Lakeflow Connect sources)"
    }
    silver = {
      comment = "Cleansed data (Lakeflow pipelines)"
    }
    gold = {
      comment = "Business-ready data (Lakeflow pipelines)"
    }
  }
  
  # Permissions
  grants = {
    admins = {
      principal = "account users"
      privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
    }
  }
}
```

### Shared Regional Metastore Pattern (Recommended)

**Best Practice**: Use one Unity Catalog metastore per Azure region, shared by all workspaces in that region.

#### Dev Environment (First Workspace in Region)

```hcl
module "unity_catalog" {
  source = "../../modules/unity-catalog"
  
  # Auto-provision regional metastore (first workspace)
  use_workspace_metastore       = true  # Uses workspace's auto-provisioned metastore
  create_metastore              = false
  assign_metastore_to_workspace = false
  
  # Workspace connection
  workspace_id  = module.databricks_workspace.workspace_id
  workspace_url = module.databricks_workspace.workspace_url
  
  # Isolation configuration
  catalog_isolation_mode   = "ISOLATED"  # Workspaces can't access each other's catalogs
  enable_workspace_binding = true        # Bind storage credentials to workspace
  
  # Storage credential (managed identity)
  access_connector_id = module.databricks_workspace.access_connector_id
  
  # Dev catalog
  catalog_name = "lakehouse_dev"
  
  # External locations (data layers)
  external_locations = {
    bronze = module.storage.bronze_url
    silver = module.storage.silver_url
    gold   = module.storage.gold_url
  }
  
  # Schemas
  schemas = {
    bronze = { comment = "Raw data" }
    silver = { comment = "Cleansed data" }
    gold   = { comment = "Business-ready data" }
  }
}
```

#### Prod Environment (Reuse Existing Metastore)

```hcl
module "unity_catalog" {
  source = "../../modules/unity-catalog"
  
  # Use existing metastore from dev (same region)
  use_workspace_metastore       = false
  create_metastore              = false
  assign_metastore_to_workspace = true
  metastore_id                  = "149269a1-2dbf-4514-8c47-dbe56524b3bf"  # From dev output
  
  # Workspace connection
  workspace_id  = module.databricks_workspace.workspace_id
  workspace_url = module.databricks_workspace.workspace_url
  
  # Same isolation configuration as dev
  catalog_isolation_mode   = "ISOLATED"
  enable_workspace_binding = true
  
  # Storage credential (managed identity - prod's own)
  access_connector_id = module.databricks_workspace.access_connector_id
  
  # Prod catalog (separate from dev)
  catalog_name = "lakehouse_prod"
  
  # Prod external locations (separate storage account)
  external_locations = {
    bronze = module.storage.bronze_url
    silver = module.storage.silver_url
    gold   = module.storage.gold_url
  }
  
  # Schemas
  schemas = {
    bronze = { comment = "Raw data" }
    silver = { comment = "Cleansed data" }
    gold   = { comment = "Business-ready data" }
  }
}
```

**Get dev metastore ID**:

```bash
cd infra/envs/dev
tofu output -raw unity_catalog_metastore_id
# Output: 149269a1-2dbf-4514-8c47-dbe56524b3bf
```

**Security Isolation**:

- ✅ **ISOLATED mode**: Workspaces cannot access each other's catalogs
- ✅ **Workspace bindings**: Storage credentials are workspace-specific
- ✅ **Separate catalogs**: `lakehouse_dev` vs `lakehouse_prod`
- ✅ **Separate storage**: Different ADLS Gen2 accounts per environment

**Benefits**:

- Follows Databricks "one metastore per region" best practice
- Avoids account metastore limits (typically 10-20 per account)
- Simplifies governance and monitoring
- Maintains complete security isolation at catalog level

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| workspace_id | Databricks workspace ID | string | Yes |
| workspace_url | Databricks workspace URL | string | Yes |
| metastore_name | Name of the metastore | string | Conditional |
| storage_root | Metastore root storage URL (abfss) | string | Conditional |
| access_connector_id | Access Connector ID for credentials | string | Yes |
| catalog_name | Name of the catalog | string | Yes |
| external_locations | Map of external location names to URLs | map(string) | Yes |
| schemas | Map of schema definitions | map(object) | Yes |
| enable_system_tables | Enable Unity Catalog system tables | bool | No |
| system_table_schemas | List of system schemas to enable | list(string) | No |
| enable_volumes | Create volumes for each schema | bool | No |

## Outputs

| Name | Description |
|------|-------------|
| metastore_id | Unity Catalog metastore ID |
| catalog_id | Catalog ID |
| schema_ids | Map of schema names to IDs |
| external_location_ids | Map of external location names to IDs |

## Modern Feature Configuration

### System Tables (Recommended for Production)

Enabled by default via `enable_system_tables = true`. The `system_table_schemas` variable
controls which schemas are provisioned (default: `["access", "billing", "lineage", "query"]`).

```hcl
module "unity_catalog" {
  # ... other config

  enable_system_tables  = true
  system_table_schemas  = ["access", "billing", "lineage", "query"] # default
}
```

Grant access to system schemas via the `databricks-grants` module:

```hcl
module "databricks_grants" {
  # ... other config

  system_schema_grants = {
    access  = { stewards = { principal = "Databricks-Stewards-Prod", privileges = ["SELECT"] } }
    billing = { stewards = { principal = "Databricks-Stewards-Prod", privileges = ["SELECT"] } }
    lineage = { stewards = { principal = "Databricks-Stewards-Prod", privileges = ["SELECT"] } }
    query   = { stewards = { principal = "Databricks-Stewards-Prod", privileges = ["SELECT"] } }
  }
}
```

**Sample queries for each system schema:**

```sql
-- system.access: Who accessed which table and when?
SELECT user_name, action_name, request_params.full_name_arg AS table_name, event_time
FROM system.access.audit
WHERE service_name = 'unityCatalog' AND action_name = 'getTable'
ORDER BY event_time DESC
LIMIT 50;

-- system.billing: Daily DBU cost by workspace
SELECT usage_date, workspace_id, sku_name, SUM(usage_quantity) AS total_dbus
FROM system.billing.usage
WHERE usage_date >= CURRENT_DATE - INTERVAL 30 DAYS
GROUP BY usage_date, workspace_id, sku_name
ORDER BY usage_date DESC;

-- system.lineage: Upstream dependencies of a table
SELECT source_table_full_name, target_table_full_name, event_time
FROM system.access.table_lineage
WHERE target_table_full_name = 'lakehouse_prod.gold.customers_gold_by_country'
ORDER BY event_time DESC;

-- system.query: Slow queries in the last 24 hours
SELECT user_name, query_text, duration / 1000 AS duration_sec, end_time
FROM system.query.history
WHERE end_time >= CURRENT_TIMESTAMP - INTERVAL 24 HOURS
  AND duration > 60000  -- more than 60 seconds
ORDER BY duration DESC
LIMIT 20;
```

### Volumes for Lakeflow

```hcl
schemas = {
  bronze = {
    comment = "Raw data layer"
    volumes = {
      raw_files = {
        type    = "MANAGED"  # UC manages storage
        comment = "Raw files from Lakeflow Connect"
      }
    }
  }
  silver = {
    comment = "Cleansed data layer"
    volumes = {
      checkpoints = {
        type    = "MANAGED"
        comment = "Streaming checkpoints"
      }
    }
  }
}
```

Access volumes:

```python
# In Databricks notebook
df = spark.read.parquet("/Volumes/lakehouse_dev/bronze/raw_files/data.parquet")
```

### Checkpoint Volumes for Streaming Pipelines

Lakeflow Spark Declarative Pipelines (SDP) require checkpoint volumes to maintain streaming state:

#### Volume Naming Convention

- **bronze.checkpoints**: Streaming state for bronze ingestion (Auto Loader)
- **silver.checkpoints**: Streaming state for silver transformations
- **gold.checkpoints**: Materialized view refresh state

#### Configuration Example

Define checkpoint volumes in `catalog_schemas`:

```hcl
catalog_schemas = {
  bronze = {
    comment = "Raw data layer"
    volumes = {
      raw_files   = { type = "MANAGED", comment = "Source data files" }
      checkpoints = { type = "MANAGED", comment = "Streaming checkpoint state" }
    }
  }
  silver = {
    comment = "Cleansed data layer"
    volumes = {
      checkpoints = { type = "MANAGED", comment = "Streaming checkpoint state" }
    }
  }
  gold = {
    comment = "Business-ready data layer"
    volumes = {
      checkpoints = { type = "MANAGED", comment = "Materialized view refresh state" }
    }
  }
}
```

#### Usage in Lakeflow Pipelines

Reference checkpoint volumes in your DAB pipeline configuration:

```yaml
resources:
  pipelines:
    customers_pipeline:
      configuration:
        checkpoint_path: "/Volumes/${catalog}/${schema}/checkpoints/${pipeline_name}/"
```

#### Why Checkpoint Volumes?

- **Fault tolerance**: Resume streaming from last processed offset after failures
- **Exactly-once semantics**: Prevent duplicate records during restarts
- **State management**: Track incremental updates and watermarks
- **UC-managed**: Automatic cleanup, access control, and lifecycle management

**Reference**: [Databricks Streaming Checkpointing](https://docs.databricks.com/structured-streaming/delta-lake.html)

### Delta Sharing (Optional)

```hcl
enable_delta_sharing = true

delta_shares = {
  analytics_share = {
    recipient = "external-partner"
    tables    = ["gold.customer_analytics", "gold.sales_summary"]
  }
}
```

## Permission Model

### Recommended RBAC Structure

```hcl
grants = {
  # Platform admins - full access
  admins = {
    principal  = "account users" # TODO: Replace with admin group
    privileges = ["ALL_PRIVILEGES"]
  }
  
  # Data engineers - write to bronze/silver, read gold
  engineers = {
    principal  = "data_engineers" # TODO: Replace with AAD group
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY"]
    schemas    = ["bronze", "silver"]
  }
  
  # Data analysts - read gold only
  analysts = {
    principal  = "data_analysts" # TODO: Replace with AAD group
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
    schemas    = ["gold"]
  }
  
  # ML engineers - read all, write to ml schema
  ml_engineers = {
    principal  = "ml_engineers" # TODO: Replace with AAD group
    privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY"]
  }
}
```

## Lakeflow Integration

Unity Catalog is designed for **Lakeflow Pipelines** (next-gen DLT):

### Bronze Layer (Lakeflow Connect)

- Use external locations for source data
- Connect to SaaS apps, databases, cloud storage
- Auto-ingest with change data capture (CDC)

### Silver Layer (Lakeflow Pipelines)

- Cleansing, validation, deduplication
- Schema evolution with Delta tables
- Streaming and batch processing

### Gold Layer (Lakeflow Pipelines)

- Business-level aggregations
- Materialized views
- Optimized for analytics

## TODO: Post-Deployment Steps

After Unity Catalog setup:

1. **Configure system tables**

   ```sql
   -- Enable in workspace settings or via API
   CALL system.register_workspace('<workspace-id>');
   ```

2. **Create service principals**

   ```bash
   # For production workloads
   databricks service-principals create --display-name "prod-etl-sp"
   ```

3. **Set up Delta Sharing** (if needed)

   ```bash
   databricks shares create --name analytics-share
   ```

4. **Configure data classification**

   ```sql
   ALTER TABLE gold.customers 
   SET TAGS ('PII' = 'true', 'sensitivity' = 'high');
   ```

5. **Enable predictive optimization**

   ```sql
   ALTER TABLE gold.sales 
   SET TBLPROPERTIES ('delta.enablePredictiveOptimization' = 'true');
   ```
