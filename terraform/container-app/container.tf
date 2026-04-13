# Container App deployment: registry, logging, environment, and the app itself.
#
# This file creates the infrastructure needed to run your Docker container on Azure:
#   - A container registry (where your Docker image is stored)
#   - A logging workspace (where your app's logs go)
#   - A Container App environment (the managed compute platform)
#   - The Container App itself (your running application)
#
# PREREQUISITE: Build and push your Docker image before first terraform apply.
# The Container App will try to pull the image on creation — if it doesn't exist yet,
# the deployment will fail.
#
#   docker build --platform linux/amd64 -f container-app/Dockerfile \
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
#   (Managed identity for ACR requires a user-assigned identity,
#   which adds complexity — admin credentials are simpler for a starter.)
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
# View logs in the Azure portal: Container App -> Log stream, or query them
# with Kusto Query Language (KQL) in the Log Analytics workspace.
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project_name}-${var.environment}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# --- Container App Environment ---
# A shared compute environment where one or more Container Apps run.
# Think of it as the "cluster" that hosts your containers.
# Multiple apps can share an environment to save cost.
resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.project_name}-${var.environment}"
  location                   = data.azurerm_resource_group.main.location
  resource_group_name        = data.azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

# --- Container App ---
# The running application. Pulls your Docker image from the registry and
# runs it with the specified CPU, memory, and environment variables.
resource "azurerm_container_app" "main" {
  name                         = "ca-${var.project_name}-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = data.azurerm_resource_group.main.name

  # "Single" = only one active revision at a time. When you push a new image
  # and create a new revision, the old one is deactivated.
  revision_mode = "Single"

  # System-assigned managed identity: Azure automatically creates an identity
  # for this container app. This identity is used to read secrets from Key Vault
  # without needing an API key or connection string — Azure handles the auth
  # between the container and Key Vault internally.
  identity {
    type = "SystemAssigned"
  }

  # Credentials for pulling Docker images from the container registry.
  registry {
    server               = azurerm_container_registry.main.login_server
    username             = azurerm_container_registry.main.admin_username
    password_secret_name = "acr-password"
  }

  # The ACR password, stored as a Container App secret.
  secret {
    name  = "acr-password"
    value = azurerm_container_registry.main.admin_password
  }

  # The OpenAI API key, read from Key Vault using the managed identity.
  # The container app doesn't store the key — it fetches it from Key Vault
  # at runtime. If you rotate the key in Key Vault, the container picks up
  # the new value on restart.
  secret {
    name                = "azure-openai-api-key"
    key_vault_secret_id = "${azurerm_key_vault.main.vault_uri}secrets/azure-openai-api-key"
    identity            = "System"
  }

  template {
    # min_replicas = 0: the app scales to zero when idle (no traffic = no cost).
    # max_replicas = 1: only one instance runs at a time (sufficient for a starter).
    # Increase max_replicas if you need to handle more concurrent users.
    min_replicas = 0
    max_replicas = 1

    container {
      name   = var.project_name
      image  = "${azurerm_container_registry.main.login_server}/${var.project_name}:latest"
      cpu    = 0.5
      memory = "1Gi"

      # Environment variables passed to the container.
      # The API key comes from the Key Vault secret above.
      # The other values are passed directly from Terraform variables.
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

      # Startup probe: checks if the container has started successfully.
      # Checks TCP connectivity on port 8000 every second. If it fails 30 times
      # in a row, the container is restarted. This gives the app up to 30 seconds
      # to start up.
      startup_probe {
        transport               = "TCP"
        port                    = 8000
        initial_delay           = 1
        interval_seconds        = 1
        timeout                 = 3
        failure_count_threshold = 30
      }

      # Liveness probe: checks if the container is still running.
      # If this fails 3 times, the container is restarted. Catches cases where
      # the process is running but stuck or unresponsive.
      liveness_probe {
        transport               = "TCP"
        port                    = 8000
        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 3
      }
    }
  }

  # Ingress: how traffic reaches your container.
  # external_enabled = true: the app is accessible from the internet.
  # target_port = 8000: the port your FastAPI server listens on.
  # Easy Auth (configured in auth.tf) sits in front of this ingress,
  # so all traffic is authenticated before it reaches your container.
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
# This is what allows the container to fetch the OpenAI API key from Key Vault
# without any credentials in code. Azure handles the authentication between
# the container and Key Vault internally via the managed identity.
resource "azurerm_role_assignment" "ca_kv_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_app.main.identity[0].principal_id
}
