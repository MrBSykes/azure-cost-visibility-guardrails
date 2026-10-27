terraform {
  required_version = ">= 1.3.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  # Same state account as the network project, but its own state file, so a
  # mistake here can never touch the network (and vice versa).
  backend "azurerm" {
    resource_group_name  = "TerraformStateRG"
    storage_account_name = "sykestfstate"
    container_name       = "tfstate"
    key                  = "cost-governance.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

data "azurerm_subscription" "current" {}
