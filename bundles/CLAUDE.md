# bundles/ — Databricks Asset Bundles

## Available Bundles

- `example-lakeflow-pipeline/` — Lakeflow SDP pipeline (bronze → silver → gold) with DQ checks
- `example-etl-job/` — ETL workflow job template

## Commands

```bash
# Wrapper (recommended — auto-sets correct profile and workspace host)
./scripts/bundle-wrapper.sh <bundle-name> dev validate
./scripts/bundle-wrapper.sh <bundle-name> dev deploy
./scripts/bundle-wrapper.sh <bundle-name> dev run <pipeline-name>

# Direct (from bundle directory)
databricks bundle validate -t dev
databricks bundle deploy -t dev
databricks bundle run -t dev <pipeline-name>
pytest tests/
```

## Bundle Structure

```
bundles/{bundle-name}/
  databricks.yml          # Slim orchestrator (defines targets + includes)
  variables.yml           # Variables incl. tag inheritance from OpenTofu outputs
  src/notebooks/          # Pipeline code (@dp.table decorators / Lakeflow SDP)
  resources/pipelines/    # Pipeline resource YAML definitions
  resources/clusters/     # Job cluster definitions
  tests/                  # Unit tests (local Spark, no cluster required)
  sample-data/            # JSONL batches + generate_sample_data.py
```

Dev resources prefixed `{user_email}_` for isolation. Prod uses central names.

## GitOps Flow

```
feature branch → PR (CI validates) → merge to main (auto-deploy dev) → GitHub Release (deploy prod)
```

## Required GitHub Variables

**OIDC/Auth:**

- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` — dev OIDC (set by `bootstrap-cicd.sh`)
- `AZURE_PROD_CLIENT_ID`, `AZURE_PROD_SUBSCRIPTION_ID` — prod OIDC
- `DATABRICKS_ACCOUNT_ID` — repository variable (not secret)
- `DATABRICKS_DEV_HOST`, `DATABRICKS_PROD_HOST` — workspace URLs (auto-set after `tofu apply`)

**Bundle:**

- `BUNDLE_DEV_CATALOG_NAME` / `BUNDLE_PROD_CATALOG_NAME` — set automatically by infra deploy workflow
- `BUNDLE_PROD_SP_APP_ID` — from `tofu output workload_sp_application_id` (only if workload SP enabled)
- `BUNDLE_TAG_PROJECT`, `BUNDLE_TAG_OWNER`, `BUNDLE_TAG_COST_CENTER` — mirror `common.tfvars` tags

**Secret:**

- `AZURE_PROD_CLIENT_SECRET` — prod service principal client secret

## CI/CD

- `bundle-deploy.yml` — validate on PR, deploy to dev on merge to `main`, deploy to prod on GitHub Release
