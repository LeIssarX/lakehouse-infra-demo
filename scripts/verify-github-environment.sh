#!/usr/bin/env bash
# ==========================================================
# GitHub Environment Protection Verification Script
# ==========================================================
# Verifies that GitHub Environment protection is correctly
# configured for production deployments.
#
# Usage:
#   ./scripts/verify-github-environment.sh
#
# Requirements:
#   - GitHub CLI (gh) installed and authenticated
#   - Repository access to check environment settings
# ==========================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
# Environment to verify (dev|prod). The wizard / CI passes it as $1.
ENVIRONMENT="${1:-prod}"
# Target repo: GitHub Actions sets GITHUB_REPOSITORY; locally resolve from the
# connected repo's gh remote. Never hardcode the blueprint repo.
REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")}"
# Protection gates (required reviewers, branch policy, env-in-workflow, env
# existence) are mandatory only for prod; for other envs they are advisory.
GATING="$([ "$ENVIRONMENT" = "prod" ] && echo 1 || echo 0)"

# ==========================================================
# Functions
# ==========================================================

log_info() {
    echo -e "${BLUE}ℹ️  ${1}${NC}"
}

log_success() {
    echo -e "${GREEN}✅ ${1}${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  ${1}${NC}"
}

log_error() {
    echo -e "${RED}❌ ${1}${NC}"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gh CLI is installed
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is not installed"
        log_info "Install with: brew install gh"
        exit 1
    fi
    
    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        log_error "GitHub CLI is not authenticated"
        log_info "Authenticate with: gh auth login"
        exit 1
    fi
    
    if [[ -z "$REPO" ]]; then
        log_error "Could not determine the GitHub repository"
        log_info "Set GITHUB_REPOSITORY, or run inside a repo with a gh remote."
        exit 1
    fi

    log_success "Prerequisites met"
    log_info "Repository: ${REPO} · Environment: ${ENVIRONMENT}"
}

check_environment_exists() {
    log_info "Checking if '${ENVIRONMENT}' environment exists..."
    
    if gh api "repos/${REPO}/environments/${ENVIRONMENT}" &> /dev/null; then
        log_success "Environment '${ENVIRONMENT}' exists"
        return 0
    elif [ "$GATING" = "1" ]; then
        log_error "Environment '${ENVIRONMENT}' does not exist"
        log_info "Create it at: https://github.com/${REPO}/settings/environments"
        return 1
    else
        log_warning "No '${ENVIRONMENT}' GitHub environment (optional for '${ENVIRONMENT}')"
        return 0
    fi
}

check_required_reviewers() {
    log_info "Checking required reviewers configuration..."
    
    local response
    response=$(gh api "repos/${REPO}/environments/${ENVIRONMENT}" 2>/dev/null || echo "{}")
    
    local reviewers_count
    # jq returns nothing (not 0) when no rule matches → guard against an empty
    # value, which would break `[ -eq ]` with "integer expression expected".
    reviewers_count=$(echo "$response" | jq -r '[.protection_rules[]? | select(.type=="required_reviewers") | .reviewers | length] | add // 0' 2>/dev/null || echo "0")
    [[ -z "$reviewers_count" || "$reviewers_count" == "null" ]] && reviewers_count=0

    if [ "$reviewers_count" -eq 0 ]; then
        if [ "$GATING" = "1" ]; then
            log_error "No required reviewers configured"
            log_info "Add reviewers at: https://github.com/${REPO}/settings/environments/${ENVIRONMENT}"
            return 1
        fi
        log_info "No required reviewers (optional for '${ENVIRONMENT}')"
        return 0
    else
        log_success "Found ${reviewers_count} required reviewer(s)"
        
        # List reviewers
        echo "$response" | jq -r '.protection_rules[]? | select(.type=="required_reviewers") | .reviewers[]? | "  - \(.reviewer.login // .reviewer.name)"' 2>/dev/null || true
        
        return 0
    fi
}

check_wait_timer() {
    log_info "Checking wait timer configuration..."
    
    local response
    response=$(gh api "repos/${REPO}/environments/${ENVIRONMENT}" 2>/dev/null || echo "{}")
    
    local wait_timer
    wait_timer=$(echo "$response" | jq -r '.protection_rules[]? | select(.type=="wait_timer") | .wait_timer' 2>/dev/null || echo "null")
    
    if [ "$wait_timer" == "null" ] || [ -z "$wait_timer" ]; then
        log_warning "No wait timer configured (optional)"
        log_info "Consider adding a wait timer for critical deployments"
    else
        log_success "Wait timer configured: ${wait_timer} minutes"
    fi
}

check_deployment_branches() {
    log_info "Checking deployment branch protection..."
    
    local response
    response=$(gh api "repos/${REPO}/environments/${ENVIRONMENT}" 2>/dev/null || echo "{}")
    
    local branch_policy
    branch_policy=$(echo "$response" | jq -r '.deployment_branch_policy.protected_branches' 2>/dev/null || echo "false")
    
    if [ "$branch_policy" == "true" ]; then
        log_success "Deployment branch protection enabled"
        log_info "Custom branch rules configured"
    elif [ "$branch_policy" == "false" ]; then
        log_warning "Any branch can deploy to ${ENVIRONMENT}"
        log_info "Consider restricting to specific branches (main, release/*)"
    else
        log_warning "Could not determine deployment branch policy"
    fi
}

check_workflow_references() {
    log_info "Checking workflow configuration..."
    
    local workflow_file=".github/workflows/tofu-deploy-${ENVIRONMENT}.yml"

    if [ ! -f "$workflow_file" ]; then
        if [ "$GATING" = "1" ]; then
            log_error "Workflow file not found: ${workflow_file}"
            return 1
        fi
        log_warning "Workflow file not found: ${workflow_file} (skipping)"
        return 0
    fi

    # Check if workflow references the environment
    if grep -q "environment:.*${ENVIRONMENT}" "$workflow_file"; then
        log_success "Workflow correctly references '${ENVIRONMENT}' environment"
    elif [ "$GATING" = "1" ]; then
        log_error "Workflow does not reference '${ENVIRONMENT}' environment"
        log_info "Add 'environment: ${ENVIRONMENT}' to the deploy job"
        return 1
    else
        log_info "Workflow does not gate on an '${ENVIRONMENT}' environment (optional for '${ENVIRONMENT}')"
    fi
    
    # Check if old third-party approval action is still present
    if grep -q "trstringer/manual-approval" "$workflow_file"; then
        log_error "Old third-party approval action still present in workflow"
        log_info "Remove 'trstringer/manual-approval' step - it's replaced by native environment protection"
        return 1
    else
        log_success "No third-party approval actions found"
    fi
}

check_recent_deployments() {
    log_info "Checking recent deployments..."
    
    local deployments
    deployments=$(gh api "repos/${REPO}/deployments?environment=${ENVIRONMENT}&per_page=5" 2>/dev/null || echo "[]")
    
    local count
    count=$(echo "$deployments" | jq 'length' 2>/dev/null || echo "0")
    
    if [ "$count" -eq 0 ]; then
        log_info "No deployments found (this is normal for new setups)"
    else
        log_success "Found ${count} recent deployment(s)"
        echo "$deployments" | jq -r '.[] | "  - \(.created_at): \(.description // "No description")"' 2>/dev/null || true
    fi
}

display_summary() {
    echo ""
    echo "========================================"
    echo "Environment Protection Summary"
    echo "========================================"
    echo "Repository: ${REPO}"
    echo "Environment: ${ENVIRONMENT}"
    echo ""
    
    log_info "Next steps:"
    echo "  1. Review configuration at: https://github.com/${REPO}/settings/environments/${ENVIRONMENT}"
    echo "  2. Test approval flow: gh release create v1.0.0-test --prerelease"
    echo "  3. Monitor deployment: gh run list --workflow='Deploy to Prod' --limit 1"
    echo ""
    log_info "Documentation:"
    echo "  - Setup guide: docs/guides/github-environment-setup.md"
    echo "  - Security guide: docs/guides/security-hardening.md"
    echo ""
}

# ==========================================================
# Main Execution
# ==========================================================

main() {
    echo "======================================"
    echo "GitHub Environment Protection Checker"
    echo "======================================"
    echo ""
    
    local exit_code=0
    
    check_prerequisites || exit_code=1
    echo ""
    
    check_environment_exists || exit_code=1
    echo ""
    
    check_required_reviewers || exit_code=1
    echo ""
    
    check_wait_timer
    echo ""
    
    check_deployment_branches
    echo ""
    
    check_workflow_references || exit_code=1
    echo ""
    
    check_recent_deployments
    echo ""
    
    display_summary
    
    if [ $exit_code -eq 0 ]; then
        log_success "All checks passed! Environment protection is correctly configured."
        return 0
    else
        log_error "Some checks failed. Review the output above and fix the issues."
        return 1
    fi
}

# Run main function
main "$@"
