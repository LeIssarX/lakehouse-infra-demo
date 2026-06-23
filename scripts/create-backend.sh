#!/bin/bash
# ==========================================================
# Create Azure Storage Backend for OpenTofu State
# ==========================================================
#
# This script creates the required Azure resources for storing
# OpenTofu state remotely in Azure Blob Storage.
#
# Usage:
#   ./scripts/create-backend.sh [environment]
#
# Example:
#   ./scripts/create-backend.sh dev
#   ./scripts/create-backend.sh prod
#
# Prerequisites:
#   - Azure CLI installed and authenticated (az login)
#   - Contributor access to the subscription
#   - Sufficient permissions to create resource groups and storage accounts

set -euo pipefail

# ==========================================================
# Configuration
# ==========================================================

ENVIRONMENT="${1:-dev}"
LOCATION="${AZURE_LOCATION:-germanywestcentral}"
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"

# Project slug namespaces state storage so multiple blueprint instances can
# coexist in one subscription. See scripts/lib/project-slug.sh.
source "$(dirname "${BASH_SOURCE[0]}")/lib/project-slug.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/prompt.sh"
SLUG="$(resolve_project_slug)"

# Resource naming
RG_NAME="rg-terraform-state-${SLUG}-${ENVIRONMENT}"
STORAGE_ACCOUNT_BASE="st${SLUG}${ENVIRONMENT}"
CONTAINER_NAME="tfstate"
# Purpose=StateStorage tag lets the wizard discover this account regardless of name.
TAGS="Environment=${ENVIRONMENT} ManagedBy=OpenTofu Purpose=StateStorage Project=${SLUG}"

# ==========================================================
# Color Output
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ==========================================================
# Validation
# ==========================================================

log_info "Validating prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    log_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if logged in
if ! az account show &> /dev/null; then
    log_error "Not logged in to Azure. Run 'az login' first."
    exit 1
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|prod|sandbox)$ ]]; then
    log_warn "Environment '$ENVIRONMENT' is not standard (dev/prod/sandbox)"
    if is_interactive; then
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_warn "Non-interactive mode — continuing with non-standard environment."
    fi
fi

log_info "Using subscription: $SUBSCRIPTION_ID"
log_info "Location: $LOCATION"
log_info "Environment: $ENVIRONMENT"

# ==========================================================
# Generate Unique Storage Account Name
# ==========================================================

# Storage account names must be globally unique and 3-24 chars
# Use first 8 chars of subscription ID as suffix
SUFFIX=$(echo "$SUBSCRIPTION_ID" | tr -d '-' | cut -c1-8)
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_BASE}${SUFFIX}"

# Ensure it's within 24 character limit
if [ ${#STORAGE_ACCOUNT_NAME} -gt 24 ]; then
    STORAGE_ACCOUNT_NAME=$(echo "$STORAGE_ACCOUNT_NAME" | cut -c1-24)
fi

log_info "Storage account name: $STORAGE_ACCOUNT_NAME"

# ==========================================================
# Create Resource Group
# ==========================================================

log_info "Creating resource group: $RG_NAME"

if az group show --name "$RG_NAME" &> /dev/null; then
    log_warn "Resource group already exists, skipping creation"
else
    az group create \
        --name "$RG_NAME" \
        --location "$LOCATION" \
        --tags $TAGS
    
    log_info "Resource group created successfully"
fi

# ==========================================================
# Create Storage Account
# ==========================================================

log_info "Creating storage account: $STORAGE_ACCOUNT_NAME"

if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RG_NAME" &> /dev/null; then
    log_warn "Storage account already exists, skipping creation"
else
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RG_NAME" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --https-only true \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --tags $TAGS
    
    log_info "Storage account created successfully"
fi

# ==========================================================
# Enable Versioning and Soft Delete
# ==========================================================

log_info "Configuring storage account features..."

# Enable blob versioning (for state file history)
az storage account blob-service-properties update \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RG_NAME" \
    --enable-versioning true

# Enable soft delete (7-day retention)
az storage account blob-service-properties update \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RG_NAME" \
    --enable-delete-retention true \
    --delete-retention-days 7

log_info "Storage features configured"

# ==========================================================
# Create Container
# ==========================================================

log_info "Creating storage container: $CONTAINER_NAME"

# Get storage account key
ACCOUNT_KEY=$(az storage account keys list \
    --resource-group "$RG_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --query '[0].value' -o tsv)

# Create container
if az storage container exists \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --account-key "$ACCOUNT_KEY" \
    --query exists -o tsv | grep -q true; then
    log_warn "Container already exists, skipping creation"
else
    az storage container create \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$ACCOUNT_KEY" \
        --public-access off
    
    log_info "Container created successfully"
fi

# ==========================================================
# Configure RBAC (Optional, for OIDC)
# ==========================================================

if [ "${ENABLE_RBAC:-false}" == "true" ]; then
    log_info "Configuring RBAC for service principal..."
    
    # FIXME: Set your service principal object ID
    SP_OBJECT_ID="${SERVICE_PRINCIPAL_OBJECT_ID:-}"
    
    if [ -z "$SP_OBJECT_ID" ]; then
        log_warn "SERVICE_PRINCIPAL_OBJECT_ID not set, skipping RBAC configuration"
    else
        # Grant Storage Blob Data Contributor role
        az role assignment create \
            --assignee "$SP_OBJECT_ID" \
            --role "Storage Blob Data Contributor" \
            --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG_NAME/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"
        
        log_info "RBAC configured for service principal"
    fi
fi

# ==========================================================
# Generate Backend Configuration
# ==========================================================

log_info "Generating backend configuration..."

BACKEND_CONFIG="infra/envs/${ENVIRONMENT}/backend.hcl"

mkdir -p "infra/envs/${ENVIRONMENT}"

cat > "$BACKEND_CONFIG" << EOF
# Auto-generated by scripts/create-backend.sh
# Do not edit manually — re-run the script to regenerate.
# Passed to OpenTofu at init time:
#   tofu init -backend-config=envs/${ENVIRONMENT}/backend.hcl -reconfigure

resource_group_name  = "$RG_NAME"
storage_account_name = "$STORAGE_ACCOUNT_NAME"
container_name       = "$CONTAINER_NAME"
key                  = "${ENVIRONMENT}.tfstate"
use_oidc             = true
EOF

log_info "Backend configuration written to: $BACKEND_CONFIG"

# ==========================================================
# Inject subscription_id into tfvars
# ==========================================================

TFVARS_FILE="infra/envs/${ENVIRONMENT}/${ENVIRONMENT}.tfvars"

if [ -f "$TFVARS_FILE" ]; then
    if grep -q 'subscription_id = "XXXXXXXX' "$TFVARS_FILE"; then
        sed -i.bak "s|subscription_id = \"XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX\".*|subscription_id = \"$SUBSCRIPTION_ID\"|" "$TFVARS_FILE"
        rm -f "${TFVARS_FILE}.bak"
        log_info "subscription_id updated in $TFVARS_FILE"
    elif ! grep -q "^subscription_id" "$TFVARS_FILE"; then
        # subscription_id line missing entirely — append after environment line
        sed -i.bak "/^environment /a\\
subscription_id = \"$SUBSCRIPTION_ID\"" "$TFVARS_FILE"
        rm -f "${TFVARS_FILE}.bak"
        log_info "subscription_id injected into $TFVARS_FILE"
    else
        log_info "subscription_id already set in $TFVARS_FILE, skipping"
    fi
else
    log_warn "$TFVARS_FILE not found, skipping subscription_id injection"
fi

# ==========================================================
# Summary
# ==========================================================

echo ""
echo "=========================================================="
echo "Backend Setup Complete! ✅"
echo "=========================================================="
echo ""
echo "📋 Summary:"
echo "  Resource Group:    $RG_NAME"
echo "  Storage Account:   $STORAGE_ACCOUNT_NAME"
echo "  Container:         $CONTAINER_NAME"
echo "  Backend Config:    $BACKEND_CONFIG"
echo ""
echo "🔑 Storage Account Key (keep secure):"
echo "  $ACCOUNT_KEY"
echo ""
echo "📝 Next Steps:"
echo "  1. Review the generated backend.hcl file"
echo "  2. Initialize OpenTofu: cd infra && tofu init -backend-config=envs/${ENVIRONMENT}/backend.hcl -reconfigure"
echo "  3. (CI/CD) Set these GitHub secrets/variables:"
echo "     - STATE_SUFFIX: $SUFFIX"
echo "     - AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
echo "  4. (OIDC) Configure service principal with Storage Blob Data Contributor role"
echo ""
echo "🔒 Security Recommendations:"
echo "  - Enable storage account firewall (restrict to known IPs)"
echo "  - Use OIDC for CI/CD authentication (no keys to rotate)"
echo "  - Enable audit logging for state file access"
echo "  - Consider using Private Endpoints for production"
echo ""
echo "=========================================================="

# ==========================================================
# Export for CI/CD
# ==========================================================

if [ "${CI:-false}" == "true" ]; then
    # Running in CI/CD, export as outputs
    echo "::set-output name=resource_group::$RG_NAME"
    echo "::set-output name=storage_account::$STORAGE_ACCOUNT_NAME"
    echo "::set-output name=container::$CONTAINER_NAME"
    echo "::set-output name=suffix::$SUFFIX"
fi

# ==========================================================
# Optional: Test Backend
# ==========================================================

if [ "${TEST_BACKEND:-false}" == "true" ]; then
    log_info "Testing backend configuration..."

    cd infra

    tofu init -backend-config="envs/${ENVIRONMENT}/backend.hcl" -reconfigure
    
    if [ $? -eq 0 ]; then
        log_info "Backend test successful! ✅"
    else
        log_error "Backend test failed ❌"
        exit 1
    fi
    
    cd - > /dev/null
fi
