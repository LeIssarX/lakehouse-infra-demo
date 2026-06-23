terraform {
  required_version = ">= 1.10.0"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.21"
    }
    databricks = {
      source                = "databricks/databricks"
      version               = "~> 1.70"
      configuration_aliases = [databricks.account, databricks.workspace]
    }
  }
}
