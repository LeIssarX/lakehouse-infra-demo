# ==========================================================
# Versions & Backend
# ==========================================================

terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.21"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.70"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  # Backend configured via -backend-config flag at init time.
  # See: scripts/tofu-wrapper.sh and scripts/create-backend.sh
  #
  #   tofu init -backend-config=envs/dev/backend.hcl -reconfigure
  #   tofu init -backend-config=envs/prod/backend.hcl -reconfigure
  backend "azurerm" {}
}
