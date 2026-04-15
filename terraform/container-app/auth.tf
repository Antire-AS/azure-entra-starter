# Entra ID Easy Auth for Container App.
#
# This file does two things:
#   1. Registers your app with Microsoft Entra ID (the "app registration")
#   2. Enables Easy Auth on the Container App (the reverse proxy)
#
# HOW IT WORKS:
#   Easy Auth places a reverse proxy in front of your container. Every HTTP
#   request passes through this proxy before reaching your app.
#
#   If the user is not signed in, the proxy redirects them to Microsoft login.
#   If the user is signed in, the proxy forwards the request to your app and
#   injects HTTP headers with the user's identity:
#     - X-MS-CLIENT-PRINCIPAL-NAME: the user's email address
#     - x-ms-client-principal: base64-encoded JSON with full identity details
#
#   Your app never sees unauthenticated requests. It never validates tokens.
#   It just reads the headers to know who the user is.
#
# WHO CAN SIGN IN?
#   By default (create_access_group = false): everyone in your Entra ID tenant.
#   With a group (create_access_group = true): only members of that group.
#   See groups.tf for how group-based access works.
#
# WHY NO CLIENT SECRET?
#   Container Apps Easy Auth uses implicit flow — it gets ID tokens directly
#   from Microsoft without exchanging an authorization code. This means no
#   client secret is needed, which is one less secret to manage.
#
# PREREQUISITE — ONE-TIME ADMIN ACTION:
#   After the first `terraform apply`, an Entra ID admin must add you as Owner
#   of the app registration. Without this, Terraform can create it but not
#   update it on subsequent runs. This is an Entra ID permission, separate
#   from Azure subscription access.
#
#   Portal: Entra ID -> App registrations -> <app> -> Owners -> Add owner
#
# LOGOUT:
#   Users can sign out by visiting https://<your-app>/.auth/logout

# Look up the current user running Terraform (used to set as app owner)
data "azuread_client_config" "current" {}

# --- App Registration ---
# This tells Microsoft: "there is an app called <project>-<env>,
# and it should accept sign-ins from this organization."
resource "azuread_application" "main" {
  display_name     = "${var.project_name}-${var.environment}"
  description      = "Entra ID auth for ${var.project_name} chat"

  # "AzureADMyOrg" = only users in your Entra ID tenant can sign in.
  # No personal Microsoft accounts, no users from other organizations.
  sign_in_audience = "AzureADMyOrg"

  # Make the person running Terraform an owner of this app registration,
  # so they can update it in future terraform apply runs.
  owners = [data.azuread_client_config.current.object_id]

  # App role for agent/service access (only added when create_agent_identity = true).
  # This defines a permission called "Agent.Access" that services can be assigned.
  # Human users don't need this — they use Easy Auth with browser-based login.
  # See agents.tf for details on how agent access works.
  dynamic "app_role" {
    for_each = var.create_agent_identity ? [1] : []
    content {
      id                   = random_uuid.agent_role_id.result
      display_name         = "Agent Access"
      description          = "Allows a service or agent to call the chat API"
      value                = "Agent.Access"
      allowed_member_types = ["Application"]
      enabled              = true
    }
  }

  web {
    implicit_grant {
      # Allow Entra ID to issue ID tokens (these identify who the user is).
      id_token_issuance_enabled = true
    }
  }

  # Terraform manages redirect URIs via a separate resource below.
  # Ignore any changes to this field on the application resource itself
  # to avoid conflicts between the two.
  lifecycle {
    ignore_changes = [web[0].redirect_uris]
  }
}

# --- Service Principal ---
# A service principal is the "local instance" of the app registration in your tenant.
# The app registration defines what the app is. The service principal is how your
# tenant interacts with it. Required for Entra ID auth to work.
#
# app_role_assignment_required:
#   When false (default): any user in the tenant can sign in.
#   When true: only users or groups explicitly assigned to this app can sign in.
#   Non-assigned users see error AADSTS50105 on the Microsoft login page and
#   never reach your app. This is set via create_access_group in groups.tf.
resource "azuread_service_principal" "main" {
  client_id                    = azuread_application.main.client_id
  app_role_assignment_required = var.create_access_group
}

# --- Redirect URI ---
# After the user signs in at Microsoft, their browser is redirected back to this URL.
# Easy Auth handles this callback automatically — your code doesn't need to do anything.
#
# This is created as a separate resource (not inline on the app registration) because
# it depends on the Container App's hostname, which isn't known until the app is created.
resource "azuread_application_redirect_uris" "main" {
  application_id = azuread_application.main.id
  type           = "Web"
  redirect_uris  = ["https://${azurerm_container_app.main.ingress[0].fqdn}/.auth/login/aad/callback"]
}

# --- Easy Auth Configuration ---
# This enables the authentication reverse proxy on the Container App.
# It uses azapi_resource (which calls the Azure REST API directly) because the
# azurerm Terraform provider doesn't have a dedicated resource for this configuration.
#
# What each setting does:
#   platform.enabled = true
#     → Turn on the auth proxy
#
#   globalValidation.unauthenticatedClientAction = "RedirectToLoginPage"
#     → If someone visits without being signed in, redirect them to Microsoft login.
#       Alternatives:
#         "Return401" — return a 401 error instead of redirecting.
#         "AllowAnonymous" — let unauthenticated requests through. The proxy still
#           injects identity headers for authenticated users, but does not block
#           anonymous requests. Your app decides which routes need auth.
#           Use this when some routes must be public (webhooks, health checks)
#           and others protected (admin UI). See the allow_anonymous variable.
#
#   globalValidation.redirectToProvider = "azureactivedirectory"
#     → Use Entra ID (Azure AD) as the login provider.
#
#   identityProviders.azureActiveDirectory.registration.clientId
#     → The app registration's client ID — connects this proxy to the app identity above.
#
#   identityProviders.azureActiveDirectory.registration.openIdIssuer
#     → The URL that identifies your Entra ID tenant. The proxy uses this to validate
#       that tokens came from your organization, not someone else's.
#
#   identityProviders.azureActiveDirectory.validation.allowedAudiences
#     → Only accept tokens intended for this specific app. Prevents tokens issued
#       for a different app from being used here.
resource "azapi_resource" "container_app_auth" {
  type      = "Microsoft.App/containerApps/authConfigs@2024-03-01"
  name      = "current"
  parent_id = azurerm_container_app.main.id

  body = {
    properties = {
      platform = {
        enabled = true
      }
      globalValidation = {
        unauthenticatedClientAction = var.allow_anonymous ? "AllowAnonymous" : "RedirectToLoginPage"
        redirectToProvider           = "azureactivedirectory"
      }
      identityProviders = {
        azureActiveDirectory = {
          enabled = true
          registration = {
            clientId     = azuread_application.main.client_id
            openIdIssuer = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/v2.0"
          }
          validation = {
            allowedAudiences = [
              "api://${azuread_application.main.client_id}"
            ]
          }
        }
      }
    }
  }
}

# --- AllowAnonymous variable ---
# When true, Easy Auth lets unauthenticated requests through. The proxy still
# injects identity headers for users who ARE signed in, but does not block
# anonymous requests. Your application code decides which routes need auth.
#
# Use this when your app has both public endpoints (webhooks, health checks,
# API endpoints called by external services) and protected endpoints (admin UI)
# living in the same container.
#
# With AllowAnonymous, protected routes should check for the
# X-MS-CLIENT-PRINCIPAL-NAME header and redirect to /.auth/login/aad if absent.
# See the "Selective route protection" section in server.py for an example.
variable "allow_anonymous" {
  description = "Allow unauthenticated requests through Easy Auth. When true, your app must check auth headers on protected routes. When false (default), all routes are protected."
  type        = bool
  default     = false
}
