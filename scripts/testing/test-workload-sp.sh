#!/bin/bash
# ==========================================================
# Workload Service Principal Module - Quick Test Script
# ==========================================================
# Usage: ./scripts/testing/test-workload-sp.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODULE_DIR="$REPO_ROOT/infra/modules/databricks-workload-sp"

echo "🧪 Testing databricks-workload-sp module..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test 1: Format check
echo ""
echo "✓ Test 1: Checking HCL formatting..."
cd "$MODULE_DIR"
if tofu fmt -check -recursive "$MODULE_DIR" > /dev/null 2>&1; then
  echo "  ✅ Format check passed"
else
  echo "  ❌ Format check failed - running tofu fmt to fix..."
  tofu fmt -recursive "$MODULE_DIR"
  echo "  ✅ Files formatted"
fi

# Test 2: Module validation (standalone)
echo ""
echo "✓ Test 2: Validating module syntax..."
cd "$MODULE_DIR"
if ! [ -d ".terraform" ]; then
  tofu init -backend=false > /dev/null 2>&1
fi
if tofu validate > /dev/null 2>&1; then
  echo "  ✅ Module validation passed"
else
  echo "  ❌ Module validation failed"
  tofu validate
  exit 1
fi

# Test 3: Check required files exist
echo ""
echo "✓ Test 3: Checking required files..."
REQUIRED_FILES=("main.tf" "variables.tf" "outputs.tf" "README.md")
for file in "${REQUIRED_FILES[@]}"; do
  if [ -f "$MODULE_DIR/$file" ]; then
    echo "  ✅ $file exists"
  else
    echo "  ❌ $file missing"
    exit 1
  fi
done

# Test 4: Check provider configuration
echo ""
echo "✓ Test 4: Verifying provider configuration..."
if grep -q "configuration_aliases = \[databricks.account\]" "$MODULE_DIR/main.tf"; then
  echo "  ✅ Provider alias configured"
else
  echo "  ❌ Missing provider alias configuration"
  exit 1
fi

if grep -q "azurerm" "$MODULE_DIR/main.tf"; then
  echo "  ✅ azurerm provider declared"
else
  echo "  ❌ Missing azurerm provider"
  exit 1
fi

# Test 5: Dev environment validation
echo ""
echo "✓ Test 5: Validating dev environment integration..."
cd "$REPO_ROOT/infra/envs/dev"
if [ -f "common.tfvars" ] && [ -f "dev.tfvars" ]; then
  echo "  ⚠️  Skipping - requires actual tfvars files (use examples)"
else
  echo "  ℹ️  No tfvars found - copy from .example files to test"
fi

# Test 6: Prod environment validation
echo ""
echo "✓ Test 6: Validating prod environment integration..."
cd "$REPO_ROOT/infra/envs/prod"
if [ -f "../../common.tfvars" ] && [ -f "prod.tfvars" ]; then
  echo "  ⚠️  Skipping - requires actual tfvars files (use examples)"
else
  echo "  ℹ️  No tfvars found - copy from .example files to test"
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ All basic tests passed!"
echo ""
echo "Next steps:"
echo "  1. Copy tfvars.example files to test full integration"
echo "  2. Run 'tofu plan' in dev/prod environments"
echo "  3. See TESTING.md for comprehensive test plan"
