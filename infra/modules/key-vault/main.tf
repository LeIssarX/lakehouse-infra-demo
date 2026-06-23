# ==========================================================
# Key Vault Module
# ==========================================================

data "azurerm_client_config" "current" {}

# Generate random suffix for unique Key Vault name
resource "random_string" "kv_suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

locals {
  # Auto-generate Key Vault name if not provided
  # Format: kv-<environment>-<random>
  key_vault_name = var.key_vault_name != null ? var.key_vault_name : "kv-${var.environment}-${random_string.kv_suffix.result}"

  # Use provided tenant ID or default to current
  tenant_id = var.tenant_id != null ? var.tenant_id : data.azurerm_client_config.current.tenant_id
}

# ==========================================================
# Key Vault
# ==========================================================

resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = local.tenant_id
  sku_name            = var.sku_name

  # RBAC vs Access Policies
  rbac_authorization_enabled = var.enable_rbac_authorization

  # Soft delete settings (recommended for production)
  soft_delete_retention_days = var.enable_soft_delete ? var.soft_delete_retention_days : 7
  purge_protection_enabled   = var.enable_purge_protection

  lifecycle {
    # Azure does not allow disabling purge protection once enabled.
    # Ignore drift so existing Key Vaults with purge protection on don't fail on plan/apply.
    ignore_changes = [purge_protection_enabled]
  }

  # Network access
  public_network_access_enabled = var.enable_public_access

  # Network ACLs (only applies if public access is enabled)
  dynamic "network_acls" {
    for_each = var.enable_public_access ? [1] : []
    content {
      bypass         = "AzureServices" # Allow Azure services (including Databricks)
      default_action = length(var.allowed_ip_ranges) > 0 ? "Deny" : "Allow"

      # Allowed IP ranges
      ip_rules = var.allowed_ip_ranges
    }
  }

  tags = merge(
    var.tags,
    {
      "ManagedBy"   = "OpenTofu"
      "Module"      = "key-vault"
      "Environment" = var.environment
    }
  )
}

# ==========================================================
# RBAC Role Assignments
# ==========================================================

resource "azurerm_role_assignment" "rbac" {
  for_each = var.enable_rbac_authorization ? var.rbac_assignments : {}

  scope                = azurerm_key_vault.main.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
}

# ==========================================================
# Diagnostic Logging (Optional)
# ==========================================================

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  count = var.enable_diagnostic_logs ? 1 : 0

  name                       = "${local.key_vault_name}-diagnostics"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Audit logs
  enabled_log {
    category = "AuditEvent"
  }

  # Metrics
  enabled_metric {
    category = "AllMetrics"
  }
}

# ==========================================================
# Notes on Databricks Integration
# ==========================================================

# After Key Vault is created, create a Databricks-backed secret scope:
#
# Method 1: Using Databricks CLI
# $ databricks secrets create-scope \
#     --scope my-azure-scope \
#     --scope-backend-type AZURE_KEYVAULT \
#     --resource-id <key-vault-id> \
#     --dns-name <key-vault-uri>
#
# Method 2: Using Databricks UI
# - Navigate to https://<workspace-url>/#secrets/createScope
# - Select "Azure Key Vault"
# - Enter Key Vault resource ID and DNS name
#
# Access secrets in notebooks:
# secret_value = dbutils.secrets.get(scope="my-azure-scope", key="my-secret")
