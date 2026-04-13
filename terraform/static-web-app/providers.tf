# Terraform providers — the plugins that talk to Azure.
#
# Two providers are needed:
#   azurerm — creates Azure resources (the Static Web App itself)
#   azuread — creates the Entra ID app registration for authentication
#
# Authentication: both providers use your current `az login` session.
# Run `az login` before `terraform apply`.

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {}
}
