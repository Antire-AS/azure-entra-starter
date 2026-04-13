# Terraform providers — the plugins that talk to Azure.
#
#   azurerm — creates Azure resources (Container Apps, Key Vault, registry, etc.)
#   azapi   — calls the Azure REST API directly for Easy Auth configuration
#             (azurerm doesn't have a dedicated resource for this)
#   azuread — creates the Entra ID app registration for authentication
#   random  — generates UUIDs for app role IDs (used by agents.tf)
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
    azapi = {
      source  = "azure/azapi"
      version = "~>2.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~>3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      # Don't permanently delete Key Vault or its keys when running terraform destroy.
      # This protects against accidental data loss — deleted vaults can be recovered.
      purge_soft_delete_on_destroy       = false
      purge_soft_deleted_keys_on_destroy = false
      recover_soft_deleted_key_vaults    = true
    }
  }
}
