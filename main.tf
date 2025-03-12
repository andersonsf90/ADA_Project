# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.70.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "919b98ed-13b1-4386-8894-1bf04ef96d62"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-cx-embarque-ti"
  location = "East US"
}