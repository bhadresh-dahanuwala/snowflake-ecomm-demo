terraform {
  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.94.1" 
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.111.0"
    }
  }
  
  # TODO: Configure Azure Blob Storage as the backend for Terraform state
  # backend "azurerm" {
  #   resource_group_name  = "rg-ecomm-prod"
  #   storage_account_name = "stecommbdprod"
  #   container_name       = "tfstate"
  #   key                  = "prod.terraform.tfstate"
  # }
}

provider "snowflake" {
  role = "ACCOUNTADMIN"
}

provider "azurerm" {
  features {}
}
