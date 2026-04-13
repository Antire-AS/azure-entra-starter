# Core infrastructure: Key Vault for storing secrets securely.
#
# Azure Key Vault is a managed service for storing API keys, passwords, and
# certificates. Instead of putting your OpenAI API key in an environment variable
# or a config file, you store it in Key Vault. The Container App reads it at
# runtime using its managed identity — no key ever appears in your code or
# Terraform state.
#
# PREREQUISITE: The resource group must already exist in Azure.
#
# AFTER FIRST APPLY: Store the OpenAI API key in Key Vault:
#   az keyvault secret set --vault-name kv-<project>-<env> \
#     --name azure-openai-api-key --value <your-key>

# The resource group must already exist — Terraform references it but doesn't create it.
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Look up the current user running Terraform (used for Key Vault admin access)
data "azurerm_client_config" "current" {}

# --- Key Vault ---
# Stores the Azure OpenAI API key (and any other secrets you add later).
#
# rbac_authorization_enabled = true:
#   Access is controlled via Azure RBAC roles instead of Key Vault access policies.
#   This is the recommended approach — it uses the same permission model as the
#   rest of Azure.
#
# purge_protection_enabled = true:
#   Deleted secrets are kept for a retention period and can be recovered.
#   Prevents accidental permanent deletion.
resource "azurerm_key_vault" "main" {
  name                       = "kv-${var.project_name}-${var.environment}"
  location                   = data.azurerm_resource_group.main.location
  resource_group_name        = data.azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = true
  rbac_authorization_enabled = true
}

# Grant the person running Terraform full admin access to Key Vault.
# This lets you run `az keyvault secret set` to store the API key.
resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}
