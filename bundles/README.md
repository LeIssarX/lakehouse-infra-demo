# Bundles - Databricks Asset Bundles

> **Note:** The underlying Databricks platform can be deployed as a managed instance or with VNet Injection. See [VNet Injection Migration Guide](../docs/migration/vnet-injection.md) for network options and migration details.

This directory contains Databricks Asset Bundle templates for deploying workloads (pipelines, jobs, ML models) to the lakehouse platform.

## 🎯 What are Databricks Asset Bundles?

Databricks Asset Bundles (DAB) are the **modern, GitOps-friendly** way to deploy Databricks workloads:

- ✅ **Infrastructure as Code** for Databricks jobs, pipelines, and compute
- ✅ **Multi-environment** support (dev/prod) in one bundle
- ✅ **Git-based workflows** - no manual UI clicks
- ✅ **CI/CD integration** - deploy via GitHub Actions
- ✅ **Version control** - track all changes
- ✅ **Templating** - reusable patterns

**Why not Terraform?**  
While Terraform manages the **platform** (workspaces, Unity Catalog, networks), Asset Bundles are optimized for **workloads** (jobs, notebooks, pipelines). They're faster, more flexible, and designed for data/ML engineers.

## 📁 Available Templates

| Template | Description | Use Case |
|----------|-------------|----------|
| [example-lakeflow-pipeline](./example-lakeflow-pipeline/) | Lakeflow pipeline (raw→curated→mart) | ETL/ELT with modern Lakeflow |
| [example-etl-job](./example-etl-job/) (TODO) | Traditional workflow job | Batch ETL with Python/SQL |
| [example-ml-training](./example-ml-training/) (TODO) | ML training pipeline | Model training & registry |
| [example-streaming-job](./example-streaming-job/) (TODO) | Real-time streaming | Event processing |

## 🚀 Quick Start

### 1. Install Databricks CLI

```bash
# Install Go-based CLI (macOS)
brew tap databricks/tap && brew install databricks

# Or via GitHub releases: https://github.com/databricks/cli/releases

# Configure
databricks configure
# Enter workspace URL and token when prompted
```

### 2. Clone a Template

```bash
# Set workspace URL (required before any bundle command)
export DATABRICKS_HOST="https://adb-XXXXXXXXXX.azuredatabricks.net"
# Get your URL from: tofu output -raw databricks_workspace_url

# Choose a template
cd bundles/example-lakeflow-pipeline/

# Review configuration (slim orchestrator)
cat databricks.yml
# Variables are in variables.yml, resources in resources/pipelines/
```

### 3. Deploy to Dev

```bash
# Option 1: Using wrapper script (recommended — auto-sets correct Databricks profile)
./scripts/bundle-wrapper.sh <bundle-name> dev validate
./scripts/bundle-wrapper.sh <bundle-name> dev deploy
./scripts/bundle-wrapper.sh <bundle-name> dev run ingest_pipeline

# Option 2: Direct commands (requires DATABRICKS_CONFIG_PROFILE to be set correctly)
databricks bundle validate -t dev
databricks bundle deploy -t dev
databricks bundle run -t dev ingest_pipeline
```

### 4. Promote to Prod

```bash
# Option 1: Using wrapper script
./scripts/bundle-wrapper.sh <bundle-name> prod validate
./scripts/bundle-wrapper.sh <bundle-name> prod deploy

# Option 2: Direct commands
# Deploy to prod (approval happens via branch protection on main branch)
databricks bundle deploy -t prod
```

## 📋 Bundle Structure

Standard bundle layout (official Databricks best-practice pattern):

```text
template-name/
├── databricks.yml              # Slim orchestrator: bundle name, targets, includes
├── variables.yml               # All variable declarations (incl. tag variables)
├── README.md                   # Template documentation
├── src/                        # Source code
│   ├── notebooks/              # Databricks notebooks (DLT/Lakeflow)
│   ├── python/                 # Python modules
│   └── sql/                    # SQL files
├── resources/                  # Databricks resource definitions (split by type)
│   ├── pipelines/              # Lakeflow / DLT pipeline YAMLs
│   ├── clusters/               # Job cluster definitions (for ETL jobs)
│   ├── jobs/                   # Workflow job definitions
│   └── dashboards/             # Dashboard JSONs
└── tests/                      # Unit/integration tests
    └── test_pipeline.py
```

> **Why split?** The official Databricks CI/CD best practices recommend splitting `databricks.yml` into separate files per resource type. This keeps the orchestrator file small (~40 lines) and makes resources easy to find and review independently.

## 🎨 Multi-Environment Configuration

Bundles support environment-specific configuration. Workspace URLs are **not hardcoded** — the Databricks CLI reads `DATABRICKS_HOST` from the environment:

```yaml
# databricks.yml — no hardcoded hosts or catalog names
targets:
  dev:
    mode: development
    variables:
      environment: "dev"
      # catalog_name inherited from variables.yml or --var flag (CI/CD)
    resources:
      pipelines:
        my_pipeline:
          name: "${workspace.current_user.userName}_my_pipeline"  # personal namespace

  prod:
    mode: production
    variables:
      environment: "prod"
      # catalog_name inherited from variables.yml or --var flag (CI/CD)
    run_as:
      service_principal_name: ${var.prod_service_principal}
```

```bash
# Local: set DATABRICKS_HOST in your shell
export DATABRICKS_HOST="https://adb-xxx.azuredatabricks.net"

# CI/CD: DATABRICKS_HOST is set from the DATABRICKS_DEV_HOST / DATABRICKS_PROD_HOST
#        repo variable (automatically updated by tofu-deploy-*.yml after each infra deploy)
```

**Key Differences:**

- **Dev**: Use `${workspace.current_user.userName}` for isolation
- **Prod**: Use service principals (`run_as`) for automation

## 🔧 Common Bundle Commands

```bash
# Validate configuration
databricks bundle validate -t dev

# Deploy without running
databricks bundle deploy -t dev

# Run a specific job/pipeline
databricks bundle run -t dev <resource-name>

# Destroy deployed resources
databricks bundle destroy -t dev

# Generate schema/docs
databricks bundle schema
```

## 🌊 Lakeflow Pipelines (Recommended)

**Lakeflow Spark Declarative Pipelines (SDP)** is the next-generation pipeline API with:

- ✅ Standard Spark APIs (no custom DLT functions)
- ✅ Qualified table names for multi-schema writes
- ✅ Enhanced lineage visualization
- ✅ Simplified configuration
- ✅ **Lakeflow Connect** - Native connectors for SaaS/databases

### Example: Lakeflow SDP Pipeline

```python
# src/notebooks/lakeflow_pipeline.py
from pyspark import pipelines as dp
from pyspark.sql import SparkSession
from pyspark.sql.functions import col

spark = SparkSession.builder.getOrCreate()

# Raw table (qualified name: schema.table)
# Catalog is set at pipeline level in resources/pipelines/pipeline.yml
@dp.table(
    name="raw.customers_raw",
    comment="Raw customer data ingested via Auto Loader",
    table_properties={"pipelines.autoOptimize.managed": "true"}
)
def customers_raw():
    return spark.readStream.format("cloudFiles") \
        .option("cloudFiles.format", "json") \
        .load("/Volumes/${var.catalog_name}/raw/raw_files/customers/")

# Curated table with data quality checks
@dp.table(
    name="curated.customers_curated",
    comment="Cleansed customer data with quality checks",
    table_properties={"pipelines.autoOptimize.managed": "true"}
)
@dp.expect_or_drop("valid_email", "email IS NOT NULL")
def customers_curated():
    # Catalog implicit from pipeline config - use schema.table format
    return spark.readStream.table("raw.customers_raw") \
        .select("customer_id", "name", "email", "country")

# Mart table - business metrics
@dp.materialized_view(
    name="mart.customers_by_country",
    comment="Business-ready customer metrics by country",
    table_properties={"pipelines.autoOptimize.managed": "true"}
)
def customers_by_country():
    # Catalog implicit from pipeline config - use schema.table format
    return spark.read.table("curated.customers_curated") \
        .groupBy("country") \
        .count()
```

**Key Differences from DLT:**

- Import: `from pyspark import pipelines as dp` (not `import dlt`)
- Qualified names: `name="raw.customers_raw"` (enables multi-schema writes)
- Standard Spark: `spark.readStream.table("schema.table")` (not `dlt.read_stream()`)
- Expectations: `@dp.expect_or_drop()` (same syntax as DLT)
- **Table references**: Use `schema.table` format (catalog set at pipeline level)

### Variable Inheritance Pattern

Bundles support flexible variable resolution with the following priority (highest to lowest):

1. **CLI flag**: `databricks bundle deploy --var="catalog_name=custom_catalog"`
2. **Target override**: `targets.dev.variables.catalog_name` (in databricks.yml)
3. **Default**: `variables.catalog_name.default` (in variables.yml)

**Best Practice**: Keep targets minimal and override via CLI in CI/CD:

```bash
# CI/CD workflow passes infrastructure outputs as --var flags
databricks bundle deploy -t dev \
  --var="catalog_name=${BUNDLE_DEV_CATALOG_NAME}" \
  --var="project_tag=${BUNDLE_TAG_PROJECT}"
```

This enables custom naming conventions without editing bundle files.

→ **Migration Guide:** See [docs/migration/dlt-to-sdp.md](../docs/migration/dlt-to-sdp.md)

## 🏗️ Creating Custom Bundles

### 1. Initialize New Bundle

```bash
# Create from template
databricks bundle init

# Or copy existing template
cp -r example-lakeflow-pipeline my-new-pipeline
cd my-new-pipeline
```

### 2. Customize Configuration

Edit `databricks.yml` (targets) and `variables.yml` (variable defaults):

- Update `bundle.name` in `databricks.yml`
- Configure `targets` (dev/prod) in `databricks.yml`
- Define resources in `resources/pipelines/`, `resources/jobs/`, etc.
- Adjust variable defaults in `variables.yml`

### 3. Add Your Code

```bash
# Add notebooks
mkdir -p src/notebooks
touch src/notebooks/my_pipeline.py

# Add Python modules
mkdir -p src/python/transforms
touch src/python/transforms/__init__.py
```

### 4. Test Locally

```bash
# Unit tests
pytest tests/

# Validate bundle
databricks bundle validate
```

### 5. Deploy

```bash
databricks bundle deploy -t dev
databricks bundle run -t dev my_pipeline
```

## 🔐 Security Best Practices

### Dev Environment

- Use **personal catalog/schema** for isolation
- Use **user identity** for data access
- No long-running clusters
- Aggressive auto-termination

### Prod Environment

- Use **service principal** for jobs
- Use **dedicated catalog** (prod isolation)
- Use **Unity Catalog volumes** for data
- Enable **audit logging**
- Changes require **PR approval** (branch protection)

Example configuration:

```yaml
targets:
  prod:
    mode: production
    run_as:
      service_principal_name: "sp-prod-pipeline"
    variables:
      catalog_name: "lakehouse_prod"
      cluster_policy_id: "${resources.cluster_policies.prod_jobs.id}"
```

## 📊 Monitoring & Observability

Bundles integrate with:

- **Databricks UI** - Pipeline/job dashboards
- **Unity Catalog System Tables** - Audit logs, lineage
- **Azure Monitor** - Metrics and alerts
- **Custom dashboards** - SQL analytics

Query deployment history:

```sql
SELECT * FROM system.access.audit 
WHERE action_name = 'createPipeline'
AND request_params.bundle_name = 'my-pipeline'
ORDER BY event_time DESC;
```

## 🚦 CI/CD Integration

Bundles integrate seamlessly with GitHub Actions:

```yaml
# .github/workflows/bundle-deploy.yml (simplified)
- name: Deploy Bundle to Dev
  env:
    DATABRICKS_HOST: ${{ vars.DATABRICKS_DEV_HOST }}
  run: |
    databricks bundle deploy -t dev \
      --var="catalog_name=${{ vars.BUNDLE_DEV_CATALOG_NAME }}" \
      --var="project_tag=${{ vars.BUNDLE_TAG_PROJECT }}" \
      --var="owner_tag=${{ vars.BUNDLE_TAG_OWNER }}" \
      --var="cost_center_tag=${{ vars.BUNDLE_TAG_COST_CENTER }}" \
      --var="environment_tag=dev"
```

**Tag inheritance chain:** `common.tfvars` → `tofu output -json tags` → `gh variable set BUNDLE_TAG_*` → `bundle deploy --var`
Tags set in OpenTofu are automatically reflected on Databricks pipeline resources after each infra deployment.

See [../../.github/workflows](../../.github/workflows/) for complete examples.

## 📚 Learn More

- **Official Docs**: [Databricks Asset Bundles](https://docs.databricks.com/dev-tools/bundles/)
- **Lakeflow Guide**: [Lakeflow Pipelines](https://docs.databricks.com/workflows/lakeflow/)
- **Best Practices**: [Bundle Development](https://docs.databricks.com/dev-tools/bundles/best-practices.html)
- **Examples**: [databricks/bundle-examples](https://github.com/databricks/bundle-examples)

## 🆘 Troubleshooting

**Bundle validation fails:**

```bash
# Check YAML syntax
yamllint databricks.yml

# Verbose validation
databricks bundle validate --verbose
```

**Deployment fails:**

```bash
# Check authentication
databricks auth describe

# Verify workspace access
databricks workspace list
```

**Pipeline fails:**

```bash
# Check logs in Databricks UI
# Or via CLI
databricks pipelines runs get <run-id> --include-logs
```

## ✅ Bundle Checklist

Before deploying a bundle:

- [ ] `databricks.yml` is valid YAML
- [ ] Dev and prod targets configured
- [ ] Service principals created for prod
- [ ] Cluster policies referenced
- [ ] Unity Catalog paths correct
- [ ] Secrets managed via Key Vault scope
- [ ] Tests passing
- [ ] README updated
- [ ] GitHub Actions workflow configured

---

**Ready to deploy?** Start with [example-lakeflow-pipeline](./example-lakeflow-pipeline/README.md)
