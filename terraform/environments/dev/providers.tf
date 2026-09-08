terraform {
  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.94.1" # Use the latest stable version
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.111.0"
    }
  }

  # TODO: Configure Azure Blob Storage as the backend for Terraform state
  # backend "azurerm" {
  #   resource_group_name  = "rg-ecomm-dev"
  #   storage_account_name = "stecommbddev"
  #   container_name       = "tfstate"
  #   key                  = "dev.terraform.tfstate"
  # }
}

provider "snowflake" {
  # SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, and SNOWFLAKE_PRIVATE_KEY 
  # are expected to be provided via environment variables in GitHub Actions.
  role = "ACCOUNTADMIN"
}

provider "azurerm" {
  features {}
  # ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_SUBSCRIPTION_ID, ARM_TENANT_ID 
  # are provided via environment variables in GitHub Actions.
}
