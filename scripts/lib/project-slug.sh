#!/bin/bash
# ==========================================================
# Shared project-slug resolution for resource namespacing
# ==========================================================
# A short, sanitised identifier that namespaces the globally/tenant-scoped
# resources (state backend, CI/CD service principal, AD groups) so multiple
# blueprint instances can coexist in one Azure subscription/tenant.
#
# Resolution precedence:
#   1. $PROJECT_SLUG          (injected by the Setup Wizard, even pre-config)
#   2. project_slug  in infra/common.tfvars
#   3. project_name  in infra/common.tfvars  (sanitised)
#   4. "lakehouse"           (default)
#
# Sanitisation (MUST match the wizard frontend + backend): lowercase, keep only
# [a-z0-9], truncate to 10 chars (keeps st<slug><env><8-hash> within 24 chars).
# ==========================================================

_sanitize_slug() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1-10
}

# Extract a "key = \"value\"" string value from an HCL/tfvars file.
_tfvars_value() {
  local key="$1" file="$2"
  [[ -f "$file" ]] || return 0
  grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" | head -1 \
    | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/'
}

resolve_project_slug() {
  local raw="${PROJECT_SLUG:-}"

  if [[ -z "$raw" ]]; then
    local repo_root common
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    common="$repo_root/infra/common.tfvars"
    raw="$(_tfvars_value project_slug "$common")"
    [[ -z "$raw" ]] && raw="$(_tfvars_value project_name "$common")"
  fi

  [[ -z "$raw" ]] && raw="lakehouse"
  local slug
  slug="$(_sanitize_slug "$raw")"
  [[ -z "$slug" ]] && slug="lakehouse"
  echo "$slug"
}
