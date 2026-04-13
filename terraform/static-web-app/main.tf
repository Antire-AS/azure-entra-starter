# Static Web App — the hosting platform.
#
# A Static Web App serves your frontend as static files (HTML/CSS/JS) and runs
# your API as Azure Functions — all as a single resource. No Docker, no servers.
#
# AFTER TERRAFORM APPLY:
#   1. Copy the tenant_id output and replace <TENANT_ID> in
#      frontend/staticwebapp.config.json — this tells the auth system
#      which Entra ID tenant to use for login.
#
#   2. Deploy your code with the SWA CLI:
#      swa deploy --app-location frontend --api-location api \
#        --deployment-token <api_key output>

# The resource group must already exist — Terraform references it but doesn't create it.
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# --- Static Web App ---
# This is the actual hosting resource. It serves the frontend and runs the API.
#
# SKU "Standard" is required for custom Entra ID authentication.
# The free tier only supports pre-configured providers (GitHub + any Microsoft account),
# which means you can't restrict sign-in to your specific tenant.
resource "azurerm_static_web_app" "main" {
  name                = "swa-${var.project_name}-${var.environment}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku_tier            = "Standard"
  sku_size            = "Standard"

  # App settings are environment variables available to your Azure Functions API.
  # They're also used by the auth system — AZURE_CLIENT_ID and AZURE_CLIENT_SECRET
  # are referenced by name in staticwebapp.config.json (clientIdSettingName /
  # clientSecretSettingName). The values come from the app registration in auth.tf.
  app_settings = {
    # Auth settings (referenced by staticwebapp.config.json)
    AZURE_CLIENT_ID     = azuread_application.main.client_id
    AZURE_CLIENT_SECRET = azuread_application_password.main.value

    # Azure OpenAI settings (used by the chat API function)
    AZURE_OPENAI_API_KEY    = var.azure_openai_api_key
    AZURE_OPENAI_ENDPOINT   = var.azure_openai_endpoint
    AZURE_OPENAI_DEPLOYMENT = var.azure_openai_deployment
    SYSTEM_PROMPT           = var.system_prompt
  }
}
