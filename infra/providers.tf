terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}

# Subscription is supplied by azd through ARM_SUBSCRIPTION_ID.
provider "azurerm" {
  features {}
}
