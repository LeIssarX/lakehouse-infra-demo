# Scripts

Helper scripts for bootstrapping, deploying, and operating the Azure Data Lakehouse platform.

## Script Overview

| Script | Purpose |
|---|---|
| [`create-backend.sh`](#create-backendsh) | Create Azure Storage backend for OpenTofu remote state |
| [`tofu-wrapper.sh`](#tofu-wrappersh) | Run OpenTofu commands with auto-loaded var files |
| [`bootstrap-cicd.sh`](#bootstrap-cicdsh) | One-time CI/CD service principal setup for GitHub Actions |
| [`bundle-wrapper.sh`](#bundle-wrappersh) | Run Databricks bundle commands with the correct CLI profile |
| [`create-azure-groups.sh`](#create-azure-groupssh) | Create Azure AD security groups for Databricks |
| [`setup-github-vars.sh`](#setup-github-varssh) | Propagate OpenTofu outputs to GitHub repository variables |
| [`verify-github-environment.sh`](#verify-github-environmentsh) | Verify GitHub Environment protection configuration |
| [`testing/validate-all.sh`](#testingvalidate-allsh) | Run syntax validation on all infrastructure modules |
| [`testing/test-workload-sp.sh`](#testingtest-workload-spsh) | Run tests specific to the `databricks-workload-sp` module |

---

## `create-backend.sh`

Creates the Azure resources required to store OpenTofu remote state, then writes the
`backend.hcl` file that `tofu init` reads.

**What it creates:**

- Azure Resource Group (`rg-terraform-state-{env}`)
- Azure Storage Account with a unique suffix (`sttfstate{env}{suffix}`)
- Blob container (`tfstate`)
- Outputs `infra/envs/{env}/backend.hcl` (gitignored)

**Usage:**

```bash
./scripts/create-backend.sh [environment]
```

**Arguments:**

| Argument | Default | Description |
|---|---|---|
| `environment` | `dev` | Target environment (`dev` or `prod`) |

**Environment variables:**

| Variable | Default | Description |
|---|---|---|
| `AZURE_LOCATION` | `westeurope` | Azure region for the state storage account |
| `AZURE_SUBSCRIPTION_ID` | current `az account` | Subscription to create resources in |

**Prerequisites:**

- Azure CLI authenticated (`az login`)
- Contributor access to the subscription

**Examples:**

```bash
./scripts/create-backend.sh dev
./scripts/create-backend.sh prod
```

---

## `tofu-wrapper.sh`

Runs OpenTofu from the `infra/` root (flat module) and automatically loads both
`common.tfvars` and the environment-specific `.tfvars` file.

Simplifies the manual command:

```bash
# Without wrapper (run from infra/):
tofu init -backend-config=envs/dev/backend.hcl -reconfigure
tofu plan -var-file=common.tfvars -var-file=envs/dev/dev.tfvars

# With wrapper:
./scripts/tofu-wrapper.sh dev init
./scripts/tofu-wrapper.sh dev plan
```

**Usage:**

```bash
./scripts/tofu-wrapper.sh <environment> <command> [extra-args...]
```

**Arguments:**

| Argument | Description |
|---|---|
| `environment` | `dev` or `prod` |
| `command` | Any OpenTofu command: `init`, `plan`, `apply`, `destroy`, `validate`, `output`, etc. |
| `extra-args` | Passed verbatim to OpenTofu (e.g. `-auto-approve`, `-target=module.storage`) |

**File loading order:**

1. `infra/common.tfvars` — global values
2. `infra/envs/{env}/{env}.tfvars` — environment-specific values
3. For `init`: also loads `infra/envs/{env}/backend.hcl` via `-backend-config`

**Examples:**

```bash
./scripts/tofu-wrapper.sh dev init              # Initialize dev backend
./scripts/tofu-wrapper.sh dev plan              # Preview changes
./scripts/tofu-wrapper.sh prod apply            # Deploy to prod
./scripts/tofu-wrapper.sh dev apply -auto-approve
./scripts/tofu-wrapper.sh dev destroy
./scripts/tofu-wrapper.sh dev output -json
./scripts/tofu-wrapper.sh dev plan -target=module.key_vault
```

---

## `bootstrap-cicd.sh`

One-time setup of the CI/CD service principal used by GitHub Actions.
Must be run before the first `tofu apply` in CI/CD.

**What it does:**

1. Creates an Azure AD App Registration + Service Principal
2. Assigns Azure roles: `Contributor` + `User Access Administrator`
3. Creates OIDC federated credentials (no long-lived secrets for OpenTofu)
4. Creates a client secret (for Databricks CLI authentication)
5. Grants `Storage Blob Data Contributor` on the OpenTofu state backend
6. Sets GitHub repository variables and secrets via `gh` CLI
7. Creates GitHub environments (`dev`: auto-deploy, `prod`: required reviewers)
8. Writes `cicd_sp_application_id` into `infra/envs/{env}/{env}.tfvars`

**Usage:**

```bash
./scripts/bootstrap-cicd.sh [environment] [--prod-reviewer GITHUB_USERNAME]
```

**Arguments:**

| Argument | Default | Description |
|---|---|---|
| `environment` | `dev` | `dev` or `prod` |
| `--prod-reviewer` | — | GitHub username to require as prod deployment reviewer |

**Prerequisites:**

- Azure CLI authenticated (`az login`)
- GitHub CLI authenticated (`gh auth login`) with repo admin access
- `jq` installed (`brew install jq`)
- OpenTofu state backend created (`create-backend.sh` run first)
- Run from repository root

**Examples:**

```bash
./scripts/bootstrap-cicd.sh dev
./scripts/bootstrap-cicd.sh prod --prod-reviewer octocat
```

> After running this script, run `tofu apply` to register the SP in Databricks.
> See [`docs/guides/cicd-setup.md`](../docs/guides/cicd-setup.md) for the full setup guide.

---

## `bundle-wrapper.sh`

Runs Databricks Asset Bundle commands with the correct CLI profile for the target environment,
preventing accidental use of unrelated profiles set in the shell.

**Usage:**

```bash
./scripts/bundle-wrapper.sh <bundle> <environment> <command> [args...]
```

**Arguments:**

| Argument | Description |
|---|---|
| `bundle` | Bundle directory name under `bundles/` (e.g. `example-lakeflow-pipeline`) |
| `environment` | `dev` or `prod` |
| `command` | Bundle command: `validate`, `deploy`, `run`, `destroy` |
| `args` | Additional arguments (e.g. pipeline or job name for `run`) |

**Environment variables:**

| Variable | Default | Description |
|---|---|---|
| `DATABRICKS_PROFILE_DEV` | `aschwabe-dev` | Databricks CLI profile name for dev |
| `DATABRICKS_PROFILE_PROD` | `aschwabe-prod` | Databricks CLI profile name for prod |

**Examples:**

```bash
./scripts/bundle-wrapper.sh example-lakeflow-pipeline dev validate
./scripts/bundle-wrapper.sh example-lakeflow-pipeline dev deploy
./scripts/bundle-wrapper.sh example-lakeflow-pipeline dev run customers_pipeline
./scripts/bundle-wrapper.sh example-lakeflow-pipeline prod deploy
./scripts/bundle-wrapper.sh example-etl-job dev validate
```

---

## `create-azure-groups.sh`

Creates Azure AD security groups for environment-specific Databricks access control.

> **Note:** This script is a workaround for environments where the CI/CD service principal
> lacks `Group.ReadWrite.All` permission. For fully automated deployments, grant that
> permission to the SP instead. See [`docs/guides/cicd-permissions.md`](../docs/guides/cicd-permissions.md).

**Groups created:**

| Group Name | Purpose |
|---|---|
| `Databricks-Admins-{Env}` | Workspace administrators |
| `Databricks-Engineers-{Env}` | Data Engineers — pipeline and cluster access |
| `Databricks-Analysts-{Env}` | Data Analysts — read access to curated data |
| `Databricks-Stewards-{Env}` | Data Stewards — governance and metadata management |
| `Databricks-Users-{Env}` | Standard users — limited dashboard access |

**Usage:**

```bash
./scripts/create-azure-groups.sh <environment>
```

**Prerequisites:**

- Azure CLI authenticated (`az login`)
- Groups Administrator role (or higher) in Azure AD

**Examples:**

```bash
./scripts/create-azure-groups.sh dev
./scripts/create-azure-groups.sh prod
```

---

## `setup-github-vars.sh`

Reads OpenTofu outputs and writes them to GitHub repository variables consumed by
the `bundle-deploy.yml` CI/CD workflow.

Run this once after the first `tofu apply` and whenever infrastructure outputs change
(e.g. new workspace URL after recreation).

**What it sets:**

| GitHub Variable | OpenTofu Output | Description |
|---|---|---|
| `DATABRICKS_DEV_HOST` / `DATABRICKS_PROD_HOST` | `workspace_url` | Workspace URL for bundle deployments |
| Additional outputs as configured | — | Any other outputs mapped to GitHub variables |

**Usage:**

```bash
./scripts/setup-github-vars.sh [environment]
```

**Arguments:**

| Argument | Default | Description |
|---|---|---|
| `environment` | `dev` | `dev` or `prod` |

**Prerequisites:**

- GitHub CLI authenticated (`gh auth login`)
- `tofu apply` already run for the environment (state must exist)
- `jq` installed (`brew install jq`)
- Run from repository root

**Examples:**

```bash
./scripts/setup-github-vars.sh dev
./scripts/setup-github-vars.sh prod
```

---

## `verify-github-environment.sh`

Verifies that GitHub Environment protection is correctly configured for the `prod` environment.
Reports whether required reviewers, wait timers, and deployment branch restrictions are enabled.

**Usage:**

```bash
./scripts/verify-github-environment.sh
```

**Environment variables:**

| Variable | Default | Description |
|---|---|---|
| `GITHUB_REPOSITORY` | `ruhragency/azure-data-lakehouse-blueprint` | Repository in `owner/repo` format |

**Prerequisites:**

- GitHub CLI authenticated (`gh auth login`)
- Read access to the repository

> See [`docs/guides/github-environment-setup.md`](../docs/guides/github-environment-setup.md) for
> setup instructions and alternative approval strategies.

---

## `testing/validate-all.sh`

Runs Level 1 (syntax-only) validation across all infrastructure modules in `infra/modules/`.
Does not require Azure credentials or a live backend.

**Checks performed:**

- `tofu fmt -check` — HCL formatting
- `tofu init -backend=false` + `tofu validate` — syntax and provider schema

**Usage:**

```bash
./scripts/testing/validate-all.sh
```

**Exit codes:**

- `0` — all modules passed
- `1` — one or more modules failed

---

## `testing/test-workload-sp.sh`

Dedicated test script for the `databricks-workload-sp` module.
Validates formatting, syntax, required files, and module-specific logic.

**Checks performed:**

- HCL format check
- Module syntax validation (standalone init + validate)
- Presence of required files (`main.tf`, `variables.tf`, `outputs.tf`, `README.md`)

**Usage:**

```bash
./scripts/testing/test-workload-sp.sh
```

---

## Prerequisites Summary

| Script | Azure CLI | GitHub CLI | jq | OpenTofu | Databricks CLI |
|---|:---:|:---:|:---:|:---:|:---:|
| `create-backend.sh` | ✅ | | | | |
| `tofu-wrapper.sh` | | | | ✅ | |
| `bootstrap-cicd.sh` | ✅ | ✅ | ✅ | | |
| `bundle-wrapper.sh` | | | | | ✅ |
| `create-azure-groups.sh` | ✅ | | | | |
| `setup-github-vars.sh` | | ✅ | ✅ | ✅ | |
| `verify-github-environment.sh` | | ✅ | | | |
| `testing/validate-all.sh` | | | | ✅ | |
| `testing/test-workload-sp.sh` | | | | ✅ | |

**Install tools:**

```bash
# macOS
brew install azure-cli gh jq opentofu databricks

# Authenticate
az login
gh auth login
```
