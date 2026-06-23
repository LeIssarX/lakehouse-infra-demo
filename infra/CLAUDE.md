# infra/ — OpenTofu Infrastructure

## Commands

```bash
# Wrapper (recommended — auto-discovers every envs/{env}/*.tfvars)
./scripts/tofu-wrapper.sh dev plan
./scripts/tofu-wrapper.sh dev apply
./scripts/tofu-wrapper.sh prod plan

# Direct (run from infra/) — pass every domain file with -var-file
tofu fmt -recursive
tofu init -backend-config=envs/dev/backend.hcl -reconfigure
tofu plan \
  -var-file=common.tfvars \
  -var-file=envs/dev/dev.tfvars \
  -var-file=envs/dev/grants.tfvars \
  -var-file=envs/dev/identity.tfvars \
  -var-file=envs/dev/compute.tfvars

# Switch to prod
tofu init -backend-config=envs/prod/backend.hcl -reconfigure
tofu plan \
  -var-file=common.tfvars \
  -var-file=envs/prod/prod.tfvars \
  -var-file=envs/prod/grants.tfvars \
  -var-file=envs/prod/identity.tfvars
```

## Variable Files

- `common.tfvars` — global values (committed)
- `envs/{dev,prod}/{dev,prod}.tfvars` — environment **core**: naming, network, security, tags
- `envs/{dev,prod}/grants.tfvars` — Unity Catalog catalog/schema grants
- `envs/{dev,prod}/identity.tfvars` — AIM group definitions
- `envs/dev/compute.tfvars` — clusters, SQL warehouses, workload SP config (dev only)
- `*.tfvars.example` — FIXME-placeholder templates (versioned)
- Wrapper script and CI workflows auto-discover every `envs/{env}/*.tfvars` —
  drop in a new domain file (e.g. `network.tfvars`) and it picks it up.

## Modules

| Module | Purpose |
|--------|---------|
| `network/` | VNet, subnets, NSGs, UDRs |
| `storage/` | ADLS Gen2 + 7-layer containers (landing/raw/curated/core/mart/reporting/sharing) + metastore |
| `databricks-workspace/` | Workspace + Access Connector |
| `key-vault/` | Azure Key Vault + secret scopes |
| `unity-catalog/` | Metastore, catalogs, schemas, volumes |
| `databricks-governance/` | Cluster/token policies |
| `databricks-aim/` | **Primary identity** — Azure AD → Databricks group sync |
| `databricks-scim/` | Legacy SCIM (optional, Premium required) |
| `databricks-compute/` | Dev clusters + SQL warehouses |
| `databricks-grants/` | Unity Catalog permissions (decoupled from catalog) |
| `databricks-workload-sp/` | Azure AD SP + Databricks registration + catalog grants |

All `.tf` files live in `infra/` root. Environments in `infra/envs/{dev,prod}/`.

## Identity (AIM — Default)

- AIM syncs Azure AD groups without SCIM or Premium license
- `databricks_account_id` only needed when enabling SCIM
- Dev groups: `Databricks-{Admins,Engineers,Analysts,Stewards,Users}-Dev`
- Prod groups: `Databricks-{Admins,Engineers,Analysts,Stewards,Users}-Prod`
- Dev engineers: `allow_cluster_create = true` | Prod engineers: `false`
- Stewards: data governance role, cross-layer Unity Catalog access

## Unity Catalog

- Shared regional metastore (one per Azure region)
- ISOLATED mode — workspaces can only access their own catalogs
- 7-layer architecture: `landing`, `raw`, `curated`, `core`, `mart`, `reporting`, `sharing`
- Volume path pattern: `/Volumes/{catalog}/{layer}/{entity}/`
- Dev: auto-provisioned metastore | Prod: references dev metastore via `existing` mode
- CI/CD SP requires `ALL_PRIVILEGES + MANAGE` on storage credential and external locations
  (auto-granted via `cicd_sp_application_id` in tfvars → unity-catalog module)

## CI/CD Workflows

- `tofu-validate.yml` — `fmt -check` + `validate` + `tfsec` on PR (dev + prod)
- `tofu-deploy-dev.yml` — deploy to dev on merge to `main` (`infra/**` changes)
- `tofu-deploy-prod.yml` — deploy to prod on GitHub Release creation or `workflow_dispatch`

## Security Controls

- Key Vault purge protection (prod): 90-day recovery window
- Audit logging: 30-day (dev) / 90-day (prod) retention in Log Analytics
- CI/CD SPs require **Databricks Account Admin** (needed by AIM module for group management)
- CI/CD SPs use Azure subscription **Contributor + User Access Administrator** roles
- CI/CD SPs require `Application.ReadWrite.OwnedBy` Graph API permission (for workload SP on prod)
- **No `Group.ReadWrite.All` required** — Azure AD groups are pre-created by `scripts/create-azure-groups.sh` (as the logged-in user) and referenced by object ID via `aim_group_ids` in `identity.tfvars`
- GitHub Actions use `contents: read` (no write)
- OIDC auth — no long-lived credentials in workflows
- See `docs/guides/security-hardening.md` for compliance checklist
