#!/bin/bash
# ==========================================================
# Validate All Modules - Syntax Check (Level 1 Testing)
# ==========================================================
# This script runs syntax validation on all infrastructure modules
#
# Usage: ./scripts/testing/validate-all.sh
# Exit code: 0 if all pass, 1 if any fail

set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILED_MODULES=()
PASSED_MODULES=()

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 Azure Lakehouse Blueprint - Validation Suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Level 1: Syntax Validation (No Azure Required)"
echo ""

# Function to validate a module
validate_module() {
  local module_path="$1"
  local module_name=$(basename "$module_path")

  echo "📦 Testing: $module_name"
  echo "   Path: $module_path"

  cd "$module_path"

  # Test 1: Format check
  if tofu fmt -check -recursive "$module_path" > /dev/null 2>&1; then
    echo "   ✅ Format check passed"
  else
    echo "   ❌ Format check failed"
    FAILED_MODULES+=("$module_name (format)")
    return 1
  fi

  # Test 2: Initialize (if not already done)
  if [ ! -d ".terraform" ]; then
    if tofu init -backend=false > /dev/null 2>&1; then
      echo "   ✅ Initialization successful"
    else
      echo "   ❌ Initialization failed"
      FAILED_MODULES+=("$module_name (init)")
      return 1
    fi
  fi

  # Test 3: Validation
  if tofu validate > /dev/null 2>&1; then
    echo "   ✅ Validation passed"
  else
    echo "   ❌ Validation failed"
    FAILED_MODULES+=("$module_name (validate)")
    return 1
  fi

  PASSED_MODULES+=("$module_name")
  echo ""
  return 0
}

# Validate all modules
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Infrastructure Modules"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

MODULES_DIR="$REPO_ROOT/infra/modules"
for module in "$MODULES_DIR"/*; do
  if [ -d "$module" ] && [ -f "$module/main.tf" ]; then
    validate_module "$module" || true
  fi
done

# Validate environments
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Environment Configurations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for env in dev prod; do
  ENV_DIR="$REPO_ROOT/infra/envs/$env"
  if [ -d "$ENV_DIR" ]; then
    echo "🏗️  Testing: $env environment"
    echo "   Path: $ENV_DIR"

    cd "$ENV_DIR"

    # Format check
    if tofu fmt -check -recursive "$ENV_DIR" > /dev/null 2>&1; then
      echo "   ✅ Format check passed"
    else
      echo "   ⚠️  Format check failed (run 'tofu fmt -recursive' to fix)"
    fi

    # Check for tfvars files
    if [ -f "../../common.tfvars" ] && [ -f "$env.tfvars" ]; then
      echo "   ℹ️  Found tfvars files - run Level 2 tests to validate configuration"
    else
      echo "   ℹ️  No tfvars files - copy from .example to test with actual config"
    fi

    echo ""
  fi
done

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Passed: ${#PASSED_MODULES[@]} modules"
for module in "${PASSED_MODULES[@]}"; do
  echo "  ✅ $module"
done

if [ ${#FAILED_MODULES[@]} -gt 0 ]; then
  echo ""
  echo "Failed: ${#FAILED_MODULES[@]} tests"
  for module in "${FAILED_MODULES[@]}"; do
    echo "  ❌ $module"
  done
  echo ""
  echo "❌ Some tests failed"
  exit 1
else
  echo ""
  echo "✅ All tests passed!"
  echo ""
  echo "Next steps:"
  echo "  1. Run Level 2 tests: Configure tfvars and run 'tofu plan'"
  echo "  2. See docs/testing/README.md for comprehensive testing guide"
  exit 0
fi
