# Databricks Governance Module

This module implements governance guardrails for Databricks workspaces including cluster policies, token policies, and compliance settings.

## Features

- **Cluster Policies** - Control compute resources, costs, and compliance
- **Token Policies** - PAT token lifetime and scope management
- **IP Access Lists** - Network security controls
- **Workload Classification** - Policy per workload type
- **Cost Controls** - Auto-termination, spot instances, node limits
- **Compliance** - Enforce Unity Catalog, serverless, security settings

## Modern Governance Patterns

### ✅ Serverless-First Policies

- Encourage serverless SQL warehouses
- Serverless workflows for jobs
- Reduce idle cluster costs

### ✅ Unity Catalog Enforcement

- Require Unity Catalog for all workloads
- Enforce `USER_ISOLATION` or `SINGLE_USER` modes
- Block legacy table ACLs

### ✅ Cost Optimization

- Auto-termination after inactivity
- Spot instance preferences
- Node type restrictions
- Pool-based policies

## Cluster Policy Types

### 1. Shared Interactive (Serverless Preferred)

For data exploration and development

- Serverless SQL warehouses (recommended)
- Small personal clusters as fallback
- Auto-termination: 30 minutes
- Unity Catalog: Required

### 2. Job Clusters (Serverless)

For production ETL/ELT workloads

- Serverless workflows (recommended)
- Single-user mode with Unity Catalog
- Spot instances for cost savings
- Auto-scaling enabled

### 3. ML Clusters

For machine learning workloads

- GPU support (optional)
- ML runtimes
- Unity Catalog for feature stores
- Larger nodes for training

### 4. Lakeflow Pipelines

For Lakeflow/DLT pipelines

- Optimized for streaming
- Enhanced autoscaling
- Unity Catalog integration
- Predictive IO

## Resources Created

- `databricks_cluster_policy` - Cluster governance policies
- `databricks_permissions` - Policy usage permissions
- `databricks_token_management` (workspace setting)
- `databricks_ip_access_list` (optional)
- `databricks_workspace_conf` - Workspace-level settings

## Usage

```hcl
module "governance" {
  source = "../../modules/databricks-governance"

  workspace_url = module.databricks_workspace.workspace_url
  environment   = "dev"
  
  # Cluster policies
  enable_cluster_policies = true
  
  # Cost controls
  max_cluster_lifetime_minutes = 120
  auto_termination_minutes     = 30
  
  # Node restrictions
  allowed_node_types = [
    "Standard_DS3_v2",      # General purpose
    "Standard_E8_v3",       # Memory optimized
    "Standard_NC6s_v3"      # GPU (optional)
  ]
  
  # Unity Catalog enforcement
  require_unity_catalog = true
  
  # Token policy
  max_token_lifetime_days = 90
  
  # IP access lists (optional)
  enable_ip_access_lists = true
  allowed_ip_ranges = [
    "10.0.0.0/8",         # Corporate network
    "203.0.113.0/24"      # Office IP
  ]
  
  # Permissions (who can use policies)
  policy_permissions = {
    data_engineers = {
      group_name = "data-engineers"
      permission_level = "CAN_USE"
    }
  }
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| workspace_url | Databricks workspace URL | string | Yes |
| environment | Environment (dev/prod/sandbox) | string | Yes |
| enable_cluster_policies | Create cluster policies | bool | No |
| require_unity_catalog | Enforce Unity Catalog | bool | No |
| max_token_lifetime_days | Max PAT token lifetime | number | No |
| allowed_node_types | List of permitted node types | list(string) | No |
| enable_ip_access_lists | Enable IP allowlisting | bool | No |
| allowed_ip_ranges | Allowed IP CIDRs | list(string) | Conditional |
| blocked_ip_ranges | Blocked IP CIDRs | list(string) | No |

> **Important — GitHub Actions CI/CD:** Databricks IP access lists have **no Azure service bypass**.
> When `enable_ip_access_lists = true`, GitHub Actions runners will be blocked from running
> `databricks bundle deploy` unless their IP ranges are included in `governance_allowed_ips`.
> Retrieve current GitHub Actions IP ranges from `https://api.github.com/meta` (field `actions`).
>
> Example `prod.tfvars`:
>
> ```hcl
> enable_ip_access_lists = true
> governance_allowed_ips = [
>   "10.0.0.0/8",         # Corporate network
>   # GitHub Actions runner IPs (verify current ranges at https://api.github.com/meta):
>   # "4.148.0.0/16",
>   # "20.1.0.0/16",
> ]
> ```

## Outputs

| Name | Description |
|------|-------------|
| cluster_policy_ids | Map of policy names to IDs |
| policy_names | List of created policy names |

## Cluster Policy Definitions

### Serverless SQL Warehouse Policy

```json
{
  "spark_version": {
    "type": "unlimited",
    "defaultValue": "auto:latest-lts"
  },
  "node_type_id": {
    "type": "unlimited"
  },
  "data_security_mode": {
    "type": "fixed",
    "value": "USER_ISOLATION"
  },
  "serverless": {
    "type": "fixed",
    "value": true
  }
}
```

### Production Job Policy

```json
{
  "autotermination_minutes": {
    "type": "fixed",
    "value": 30
  },
  "azure_attributes.spot_bid_max_price": {
    "type": "fixed",
    "value": -1
  },
  "azure_attributes.availability": {
    "type": "fixed",
    "value": "SPOT_WITH_FALLBACK_AZURE"
  },
  "data_security_mode": {
    "type": "fixed",
    "value": "SINGLE_USER"
  }
}
```

## Best Practices

### ✅ DO

- Use serverless compute wherever possible
- Enforce Unity Catalog in all policies
- Set aggressive auto-termination for dev
- Use spot instances for non-critical jobs
- Restrict node types to approved list
- Set token lifetime limits
- Enable IP allowlisting for production

### ❌ DON'T

- Allow unlimited cluster lifetimes
- Permit legacy table ACLs mode
- Allow admin privileges to all users
- Skip auto-termination settings
- Allow GPU nodes without approval
- Use shared clusters for production jobs

## Token Policy Configuration

```hcl
# Restrict PAT token lifetime
token_policy = {
  max_lifetime_days           = 90   # Max 90 days
  require_authorization_token = true # MFA required
}
```

## IP Access Lists

```hcl
# Production: Lock down to corporate network
ip_access_lists = {
  corporate_network = {
    list_type = "ALLOW"
    ip_addresses = [
      "10.0.0.0/8",
      "172.16.0.0/12"
    ]
  }
  
  # Block specific ranges
  blocked_ranges = {
    list_type = "BLOCK"
    ip_addresses = [
      "192.0.2.0/24"
    ]
  }
}
```

## Compliance Features

```hcl
compliance_settings = {
  # Require enhanced security
  enhanced_security_monitoring = true
  
  # Disable public IPs on clusters
  no_public_ip = true
  
  # Enforce encryption at rest
  encryption_at_rest = true
  
  # Enable audit logs
  audit_log_delivery = true
}
```

## TODO: Post-Deployment

1. **Assign policies to groups**

   ```bash
   databricks permissions update cluster-policies \
     --cluster-policy-id policy-id \
     --group data-engineers --permission-level CAN_USE
   ```

2. **Test policies**
   - Try creating a cluster with each policy
   - Verify restrictions are enforced
   - Check cost controls work

3. **Monitor policy usage**

   ```sql
   SELECT * FROM system.access.audit
   WHERE action_name = 'createCluster'
   AND request_params.cluster_policy_id IS NOT NULL;
   ```

4. **Review and update**
   - Quarterly review of node types
   - Update based on new workload requirements
   - Adjust cost controls as needed
