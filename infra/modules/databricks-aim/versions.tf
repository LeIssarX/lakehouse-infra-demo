terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    databricks = {
      source                = "databricks/databricks"
      version               = "~> 1.70"
      configuration_aliases = [databricks.account, databricks.workspace]
    }
  }
}
