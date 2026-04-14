# Terraform providers — the plugins that talk to Azure.
#
#   azurerm — creates Azure resources (Container Apps, Key Vault, registry, etc.)
#   azuread — creates the Entra ID app registration for authentication
#
# NOTE: This option does NOT use the azapi provider. The Easy Auth option
# needs azapi to configure the auth proxy via the Azure REST API. With MSAL,
# there is no auth proxy — the app handles auth itself — so azapi is not needed.
#
# Authentication: the Azure providers use your current `az login` session.
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
  features {
    key_vault {
      purge_soft_delete_on_destroy       = false
      purge_soft_deleted_keys_on_destroy = false
      recover_soft_deleted_key_vaults    = true
    }
  }
}
