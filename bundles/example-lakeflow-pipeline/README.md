# Example: Lakeflow Pipeline

This is a production-ready **Databricks Asset Bundle** template for a **Lakeflow Spark Declarative Pipeline (SDP)** — the next-generation pipeline API using standard Spark syntax.

## 🎯 What This Does

Implements a **7-layer lakehouse architecture** pipeline:

1. **Raw**: Ingest raw JSON files from ADLS (via Auto Loader)
2. **Curated**: Cleanse, validate, and enrich data
3. **Mart**: Create business-ready aggregations

## 🏗️ Pipeline Architecture

```text
Source Files (ADLS)
    ↓
┌─────────────────┐
│  Raw Layer      │  ← Raw ingestion (Auto Loader)
│  customers_raw  │
└─────────────────┘
    ↓ (Lakeflow SDP transformation)
┌─────────────────┐
│  Curated Layer  │  ← Data quality checks
│  customers_curated │
└─────────────────┘
    ↓ (Aggregation)
┌─────────────────┐
│  Mart Layer     │  ← Business metrics
│  customers_by_* │
└─────────────────┘
```

## 📁 Bundle Structure

```text
example-lakeflow-pipeline/
├── databricks.yml                        # Slim orchestrator: bundle name, targets, includes
├── variables.yml                         # All variable declarations (including tag variables)
├── README.md                             # This file
├── src/
│   └── notebooks/
│       ├── raw/
│       │   └── customers_raw.py          # Auto Loader ingestion → raw.customers_raw
│       ├── curated/
│       │   └── customers_curated.py      # DQ + enrichment → curated.customers_curated
│       └── mart/
│           └── customers_mart.py         # Aggregations → mart.customers_by_*
├── resources/
│   ├── pipelines/
│   │   └── customers_pipeline.yml        # Pipeline resource definition
│   ├── clusters/                         # Job-cluster definitions (future ETL bundles)
│   └── dashboards/                       # Dashboard JSON definitions (future)
└── tests/
    └── test_pipeline.py                  # Unit tests (local Spark, no cluster required)
```

## 🚀 Quick Start

### Prerequisites

```bash
# Install Databricks CLI (Go-based)
# macOS:
brew install databricks/tap/databricks
# Other platforms: https://docs.databricks.com/dev-tools/cli/install.html

# Set workspace URL — required before any bundle command
# Option A: Environment variable (recommended, works with all tools)
export DATABRICKS_HOST="https://adb-XXXXXXXXXX.azuredatabricks.net"
# Get your URL from: Azure Portal → Databricks service → Overview → URL
# Or after infra deploy: tofu output -raw databricks_workspace_url

# Option B: Interactive profile (stored in ~/.databrickscfg)
databricks configure

# Navigate to this bundle
cd bundles/example-lakeflow-pipeline/
```

### Deploy to Dev

```bash
# Option 1: Using wrapper script (recommended — auto-sets correct Databricks profile)
./scripts/bundle-wrapper.sh example-lakeflow-pipeline dev validate
./scripts/bundle-wrapper.sh example-lakeflow-pipeline dev deploy
./scripts/bundle-wrapper.sh example-lakeflow-pipeline dev run customers_pipeline

# Option 2: Direct commands
databricks bundle validate -t dev
databricks bundle deploy -t dev
databricks bundle run -t dev customers_pipeline
```

### Monitor Pipeline

```bash
# View in Databricks UI
open https://your-workspace.azuredatabricks.net/#/pipelines/<pipeline-id>

# Or via CLI
databricks pipelines runs list --pipeline-id <pipeline-id>
databricks pipelines runs get <run-id> --include-logs
```

### Deploy to Prod

```bash
# Deploy (approval happens via PR review on main branch)
databricks bundle deploy -t prod

# Trigger run
databricks bundle run -t prod customers_pipeline
```

## ⚙️ Configuration

### Environment Variables

The bundle uses environment-specific configs:

| Variable | Dev | Prod | Source |
|----------|-----|------|--------|
| catalog_name | `lakehouse_dev` (default) | `lakehouse_prod` (default) | variables.yml or --var flag |
| compute | Serverless | Serverless | Pipeline config |
| mode | `development` | `production` | Target config |
| run_as | Current user | Service principal | Target config |

### Variable Inheritance

The bundle follows a strict variable resolution order:

1. **CLI flag** (highest priority): `--var="catalog_name=custom_catalog"`
2. **Target override**: `targets.dev.variables.catalog_name` in databricks.yml
3. **Default value** (lowest priority): `variables.catalog_name.default` in variables.yml

**CI/CD Pattern**: Infrastructure outputs → GitHub variables → Bundle CLI flags

```bash
# Example: CI/CD automatically passes custom names
databricks bundle deploy -t dev \
  --var="catalog_name=${BUNDLE_DEV_CATALOG_NAME}" \
  --var="project_tag=${BUNDLE_TAG_PROJECT}"
```

**Benefit**: Supports custom naming conventions without editing bundle files.

### Service Principal Setup (Production)

Production pipelines run as a dedicated service principal rather than a user account.
This follows the principle of least privilege and avoids dependency on personal access tokens.

#### Option 1: Automated (Recommended) - OpenTofu Module

The workload service principal is **automatically created** via the `databricks-workload-sp` module in the infrastructure code:

1. **Enable the module in your production environment**:

   ```hcl
   # infra/envs/prod/prod.tfvars
   enable_workload_sp = true

   workload_sp_catalog_grants = {
     "lakehouse_prod" = ["USE CATALOG"]
   }

   workload_sp_schema_grants = {
     "lakehouse_prod.raw"     = ["USE SCHEMA", "SELECT"]
     "lakehouse_prod.curated" = ["USE SCHEMA", "SELECT", "MODIFY"]
     "lakehouse_prod.mart"    = ["USE SCHEMA", "SELECT", "MODIFY"]
   }
   ```

2. **Deploy the infrastructure**:

   ```bash
   cd infra/envs/prod
   tofu apply
   ```

3. **Get the application ID** from OpenTofu output:

   ```bash
   tofu output workload_sp_application_id
   ```

4. **Configure your bundle** with the output value:

   ```bash
   export DATABRICKS_PROD_SP="<application-id-from-output>"
   databricks bundle deploy -t prod --var prod_service_principal=$DATABRICKS_PROD_SP
   ```

See `infra/modules/databricks-workload-sp/README.md` for detailed module documentation.

#### Option 2: Manual Setup (Legacy)

If you prefer manual setup or cannot use the OpenTofu module:

**Steps:**

1. **Create a service principal in Azure AD** (or use an existing one):

   ```bash
   az ad sp create-for-rbac --name "sp-lakehouse-pipeline-prod"
   ```

2. **Add the SP to the Databricks workspace** as a service principal:
   - Databricks UI → Settings → Identity and access → Service principals → Add

3. **Grant Unity Catalog permissions** (minimum required):

   ```sql
   GRANT USE CATALOG ON CATALOG lakehouse_prod TO `<sp-application-id>`;
   GRANT USE SCHEMA, SELECT ON SCHEMA lakehouse_prod.raw TO `<sp-application-id>`;
   GRANT USE SCHEMA, MODIFY ON SCHEMA lakehouse_prod.curated TO `<sp-application-id>`;
   GRANT USE SCHEMA, MODIFY ON SCHEMA lakehouse_prod.mart TO `<sp-application-id>`;
   ```

4. **Configure the bundle variable** — either set it in `terraform.tfvars` style or pass it during deploy:

   ```bash
   databricks bundle deploy -t prod \
     --var="prod_service_principal=<sp-application-id>"
   ```

   Or set it as a GitHub Actions secret and reference it with `--var` in the workflow.

### Customization

#### Option 1: Override at deploy time (recommended for CI/CD)

```bash
# Pass custom values via --var flags
databricks bundle deploy -t dev \
  --var="catalog_name=my_custom_catalog" \
  --var="owner_tag=MyTeam"
```

#### Option 2: Edit defaults (for local development)

```yaml
# variables.yml — change defaults
variables:
  catalog_name:
    default: "my_catalog"
  source_path:
    default: "/Volumes/${var.catalog_name}/raw/raw_files/customers/"
```

**Why CLI overrides?** Keeps bundle configuration DRY and enables infrastructure-driven naming without editing files.

## 📊 Data Quality

The pipeline includes built-in data quality checks:

```python
# In customers_pipeline.py
@dp.expect_or_drop("valid_email", "email IS NOT NULL AND email LIKE '%@%'")
@dp.expect_or_fail("valid_customer_id", "customer_id IS NOT NULL")
@dp.expect("valid_country", "country IS NOT NULL", "warn")
```

### Quality Monitoring

View quality metrics in Databricks UI:

- **Expectations**: Rules applied to data
- **Dropped records**: Records that failed quality checks
- **Warnings**: Non-blocking quality issues

## 🔄 Continuous Updates

Lakeflow pipelines support **continuous processing**:

```yaml
# In lakeflow_pipeline.yml
continuous: true  # Run continuously (streaming mode)
# OR
continuous: false # Run in triggered/scheduled mode
```

## 🧪 Testing

### Unit Tests

```bash
# Run locally with pytest
pytest tests/test_pipeline.py

# With coverage
pytest --cov=src tests/
```

### Test Coverage

The test suite (`tests/test_pipeline.py`) contains 11 unit tests covering all three active lakehouse layers:

| Category | Tests |
|----------|-------|
| Raw | Schema validation, row count ingestion |
| Curated | Invalid record removal, email validation, date conversion, days-since-signup |
| Mart | Country aggregation, daily signup aggregation |
| Edge cases | Empty dataframe, duplicate customer IDs, null country handling |

Tests run locally against a `local[2]` Spark session — no Databricks cluster required.

### Running Tests Locally

```bash
# Install test dependencies
pip install pytest pyspark delta-spark pytest-cov

# Run all tests
pytest tests/test_pipeline.py -v

# Run with coverage report
pytest --cov=src tests/
```

### Adding Tests

New tests go in `tests/test_pipeline.py`. Follow the existing pattern:

1. Use the `spark` session fixture (session-scoped, shared across tests)
2. Create focused DataFrames with `spark.createDataFrame(data, schema)`
3. Apply transformation logic inline and assert the result

### Integration Tests

For end-to-end validation, deploy to dev and verify pipeline output:

```bash
# Deploy to dev and run
databricks bundle deploy -t dev
databricks bundle run -t dev customers_pipeline --wait

# Verify outputs
databricks sql execute \
  "SELECT COUNT(*) FROM lakehouse_dev.mart.customers_by_country"
```

## 📝 Sample Data

### Input Format (Raw)

```json
{
  "customer_id": "C001",
  "name": "John Doe",
  "email": "john@example.com",
  "country": "USA",
  "signup_date": "2024-01-15",
  "status": "active"
}
```

### Output Format (Mart)

| country | customer_count | active_customers | avg_days_since_signup |
|---------|----------------|------------------|------------------------|
| USA     | 1500           | 1200             | 45                     |
| Germany | 800            | 650              | 60                     |

### Generating Test Data

The pipeline includes a sample data generator for local testing and development.

#### Generate Sample Files

```bash
cd sample-data/
python generate_sample_data.py
```

**Output**: Creates 3 batch files (~250 customer records total) in JSONL format:

- `customers_batch_01.jsonl` (83-88 records)
- `customers_batch_02.jsonl` (83-88 records)
- `customers_batch_03.jsonl` (83-88 records)

#### Upload to Unity Catalog Volume

```bash
# Upload to raw landing zone
databricks fs cp customers_batch_01.jsonl \
  dbfs:/Volumes/lakehouse_dev/raw/raw_files/customers/

# Or bulk upload all batches
databricks fs cp sample-data/*.jsonl \
  dbfs:/Volumes/lakehouse_dev/raw/raw_files/customers/ --recursive
```

#### Sample Data Schema

Each generated record contains realistic SaaS customer data:

| Field | Type | Description | Example Values |
|-------|------|-------------|----------------|
| `customer_id` | string | Unique UUID | `a3b2c1d4-...` |
| `company_name` | string | Realistic company names | `Acme Corp`, `TechStart GmbH` |
| `email` | string | Valid email addresses | `contact@acme.com` |
| `country` | string | ISO country codes | `US`, `DE`, `FR`, `GB` |
| `city` | string | City names | `New York`, `Berlin` |
| `industry` | string | Industry vertical | `Technology`, `Healthcare` |
| `signup_date` | string | ISO date (2020-2025) | `2024-01-15` |
| `plan` | string | Subscription tier | `free`, `starter`, `professional`, `enterprise` |
| `status` | string | Customer status | `active`, `trial`, `churned` |
| `mrr` | integer | Monthly recurring revenue | `0-5000` |
| `employees` | integer | Company size | `1-5000` |

#### Testing the Pipeline

1. Generate and upload sample data (steps above)
2. Run the pipeline: `databricks bundle run -t dev customers_pipeline`
3. View results:

   ```sql
   -- Raw (ingested data)
   SELECT * FROM <catalog_name>.raw.customers_raw LIMIT 10;

   -- Curated (cleansed data)
   SELECT * FROM <catalog_name>.curated.customers_curated LIMIT 10;

   -- Mart (aggregated metrics)
   SELECT * FROM <catalog_name>.mart.customers_by_country ORDER BY customer_count DESC;
   ```

   Replace `<catalog_name>` with your actual catalog (default: `lakehouse_dev` for dev).

## 🔐 Security

### Dev Environment

- Uses **your user identity** for data access
- Writes to **personal dev schema** (optional)
- No production data access

### Prod Environment

- Uses **service principal** for automation
- Writes to **prod catalog** (isolated)
- Audit logs enabled
- Changes require **PR approval** (branch protection)

## 🎛️ Monitoring & Alerts

### Built-in Monitoring

Lakeflow provides:

- **Pipeline health dashboard**
- **Data quality metrics**
- **Lineage tracking**
- **Performance metrics**

### Custom Alerts

Configure alerts in Databricks:

```yaml
# In lakeflow_pipeline.yml
alerts:
  - name: "Pipeline Failure"
    type: "ON_FAILURE"
    email_recipients:
      - "data-team@company.com"
  
  - name: "Quality Issues"
    type: "ON_QUALITY_EXPECTATIONS"
    slack_webhook: "https://hooks.slack.com/..."
```

## 🚀 Advanced Features

### Lakeflow Connect (Source Connectors)

Replace file ingestion with native connectors:

```python
# Example: Connect to Salesforce
@dp.table(name="raw.salesforce_accounts")
def salesforce_accounts():
    return spark.readStream.table("lakeflow_connect.salesforce.accounts")
```

Supported sources:

- Salesforce, Workday, SAP
- MySQL, PostgreSQL, SQL Server
- MongoDB, Cassandra
- S3, GCS, ADLS

### Change Data Capture (CDC)

Handle updates and deletes:

```python
@dp.table(name="curated.customers_curated_scd2")
def customers_curated_scd2():
    return spark.readStream.table("lakehouse_dev.raw.customers_raw") \
        .apply_changes(
            keys=["customer_id"],
            sequence_by="updated_at",
            stored_as_scd_type=2
        )
```

### Materialized Views

Create optimized views:

```python
@dp.materialized_view(name="mart.customer_360")
def customer_360():
    return spark.read.table("lakehouse_dev.curated.customers_curated") \
        .join(spark.read.table("lakehouse_dev.curated.orders_curated"), "customer_id")
```

## 📈 Performance Optimization

### Auto-Optimization

Lakeflow automatically:

- ✅ Optimizes file sizes (compaction)
- ✅ Maintains Z-order clustering
- ✅ Vacuum old files
- ✅ Caches hot data

### Manual Optimization

```python
# In pipeline definition - use table properties
@dp.table(
    name="curated.customers_curated",
    partition_cols=["country"],
    table_properties={
        "delta.autoOptimize.optimizeWrite": "true",
        "delta.autoOptimize.autoCompact": "true"
    }
)
def customers_curated():
    # Z-order optimization applied via table properties
    return spark.readStream.table("lakehouse_dev.raw.customers_raw")
```

## 🐛 Troubleshooting

### Pipeline won't deploy

```bash
# Check configuration
databricks bundle validate --verbose -t dev

# Verify workspace permissions
databricks workspace list /Users/your-username/

# Check Unity Catalog access
databricks catalogs list
```

### Pipeline fails during run

1. **Check logs** in Databricks UI
2. **Verify source data** exists
3. **Check permissions** on Unity Catalog
4. **Test transformations** in notebook

### Data quality failures

```sql
-- Query quality metrics
SELECT *  
FROM event_log('<pipeline-id>')
WHERE event_type = 'flow_progress'
AND origin.update_id = '<update-id>';
```

## 📚 Learn More

- **Lakeflow Docs**: [docs.databricks.com/workflows/lakeflow](https://docs.databricks.com/workflows/lakeflow/)
- **Lakeflow SDP API**: [learn.microsoft.com/azure/databricks/ldp/](https://learn.microsoft.com/en-us/azure/databricks/ldp/)
- **Migration from DLT**: [docs/migration/dlt-to-sdp.md](../../docs/migration/dlt-to-sdp.md)
- **Asset Bundles**: [docs.databricks.com/dev-tools/bundles](https://docs.databricks.com/dev-tools/bundles/)

## ✅ Deployment Checklist

- [ ] Databricks CLI configured
- [ ] Bundle validated (`databricks bundle validate`)
- [ ] Source data uploaded to raw volume
- [ ] Unity Catalog permissions granted
- [ ] Service principal created (for prod)
- [ ] Tests passing
- [ ] Deployed to dev and tested
- [ ] PR approved for prod deployment

---

**Next**: Customize this template for your use case or explore [other templates](../README.md)
