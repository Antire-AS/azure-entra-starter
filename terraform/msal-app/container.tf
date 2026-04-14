# Container App deployment: registry, logging, environment, and the app itself.
#
# This file creates the infrastructure needed to run your Docker container on Azure:
#   - A container registry (where your Docker image is stored)
#   - A logging workspace (where your app's logs go)
#   - A Container App environment (the managed compute platform)
#   - The Container App itself (your running application)
#
# KEY DIFFERENCE FROM THE EASY AUTH OPTION:
#   There is no Easy Auth proxy. The Container App receives requests directly.
#   Authentication is handled by:
#     1. The frontend (MSAL.js) — acquires tokens from Microsoft
#     2. The backend (FastAPI) — validates JWT tokens on every request
#
#   This means unauthenticated requests CAN reach your backend. The backend
#   is responsible for rejecting them (it returns 401 if the token is missing
#   or invalid).
#
# PREREQUISITE: Build and push your Docker image before first terraform apply.
# The Container App will try to pull the image on creation — if it doesn't exist yet,
# the deployment will fail.
#
#   docker build --platform linux/amd64 -f msal-app/Dockerfile \
#     -t <registry>/<project>:latest .
#   az acr login --name <registry>
#   docker push <registry>/<project>:latest

# --- Container Registry ---
# Azure Container Registry (ACR) stores your Docker images.
# Think of it as a private Docker Hub for your organization.
#
# admin_enabled = true:
#   Enables username/password authentication for pulling images.
#   The Container App uses these credentials to pull your image.
resource "azurerm_container_registry" "main" {
  name                          = replace("cr${var.project_name}${var.environment}", "-", "")
  location                      = data.azurerm_resource_group.main.location
  resource_group_name           = data.azurerm_resource_group.main.name
  sku                           = "Basic"
  admin_enabled                 = true
  public_network_access_enabled = true
}

# --- Log Analytics ---
# Collects logs from the Container App for monitoring and troubleshooting.
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${var.environment}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# --- Container App Environment ---
# A shared compute environment where one or more Container Apps run.
resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.project_name}-${var.environment}"
  location                   = data.azurerm_resource_group.main.location
  resource_group_name        = data.azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

# --- Container App ---
# The running application. Pulls your Docker image from the registry and
# runs it with the specified CPU, memory, and environment variables.
#
# NOTE: No Easy Auth configuration here. Compare this with the Easy Auth option's
# container.tf + auth.tf — that option has an azapi_resource that configures the
# auth proxy. Here, the Container App is "open" and the backend handles auth.
resource "azurerm_container_app" "main" {
  name                         = "ca-${var.project_name}-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = data.azurerm_resource_group.main.name

  revision_mode = "Single"

  identity {
    type = "SystemAssigned"
  }

  registry {
    server               = azurerm_container_registry.main.login_server
    username             = azurerm_container_registry.main.admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = azurerm_container_registry.main.admin_password
  }

  secret {
    name                = "azure-openai-api-key"
    key_vault_secret_id = "${azurerm_key_vault.main.vault_uri}secrets/azure-openai-api-key"
    identity            = "System"
  }

  template {
    min_replicas = 0
    max_replicas = 1

    container {
      name   = var.project_name
      image  = "${azurerm_container_registry.main.login_server}/${var.project_name}:latest"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name        = "AZURE_OPENAI_API_KEY"
        secret_name = "azure-openai-api-key"
      }

      env {
        name  = "AZURE_OPENAI_ENDPOINT"
        value = var.azure_openai_endpoint
      }

      env {
        name  = "AZURE_OPENAI_DEPLOYMENT"
        value = var.azure_openai_deployment
      }

      env {
        name  = "SYSTEM_PROMPT"
        value = var.system_prompt
      }

      # These are used by the backend to validate JWT tokens.
      # The backend needs to know which tenant and app the tokens should be for.
      env {
        name  = "AZURE_TENANT_ID"
        value = data.azuread_client_config.current.tenant_id
      }

      env {
        name  = "AZURE_CLIENT_ID"
        value = azuread_application.main.client_id
      }

      startup_probe {
        transport               = "TCP"
        port                    = 8000
        initial_delay           = 1
        interval_seconds        = 1
        timeout                 = 3
        failure_count_threshold = 30
      }

      liveness_probe {
        transport               = "TCP"
        port                    = 8000
        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 3
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8000

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

# Grant the Container App's managed identity read access to Key Vault secrets.
resource "azurerm_role_assignment" "ca_kv_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_app.main.identity[0].principal_id
}
