# Entra ID App Registration for MSAL (client-side auth).
#
# This file registers your app with Microsoft Entra ID so that the MSAL library
# in the browser can perform login and acquire tokens.
#
# HOW THIS DIFFERS FROM EASY AUTH:
#
#   Easy Auth:  Azure places a reverse proxy in front of your app that handles login.
#               Your code never sees tokens — it reads HTTP headers.
#               No auth library needed. No token validation code.
#
#   MSAL:       Your frontend JavaScript handles login using the MSAL library.
#               The browser acquires tokens directly from Microsoft.
#               Your backend validates the tokens itself.
#               More code, but also more control and portability.
#
# APP TYPE: Single Page Application (SPA)
#
#   The app registration is configured as a SPA, not a Web app. The difference:
#
#     Web app:   Uses authorization code flow with a client secret.
#                The server exchanges a code for tokens. The secret must be kept
#                safe on the server — it never goes to the browser.
#
#     SPA:       Uses authorization code flow with PKCE (Proof Key for Code Exchange).
#                The browser exchanges a code for tokens without a secret.
#                PKCE replaces the secret with a dynamically generated challenge.
#                No secret to manage or rotate. This is the recommended flow for
#                JavaScript apps that run in the browser.
#
# WHO CAN SIGN IN?
#   By default (create_access_group = false): everyone in your Entra ID tenant.
#   With a group (create_access_group = true): only members of that group.
#   See groups.tf for how group-based access works.
#
# PREREQUISITE — ONE-TIME ADMIN ACTION:
#   After the first `terraform apply`, an Entra ID admin must add you as Owner
#   of the app registration. Without this, Terraform can create it but not
#   update it on subsequent runs. This is an Entra ID permission, separate
#   from Azure subscription access.
#
#   Portal: Entra ID -> App registrations -> <app> -> Owners -> Add owner

# Look up the current user running Terraform (used to set as app owner)
data "azuread_client_config" "current" {}

# --- App Registration ---
# This tells Microsoft: "there is an app called <project>-<env>,
# and it should accept sign-ins from this organization."
resource "azuread_application" "main" {
  display_name = "${var.project_name}-${var.environment}"
  description  = "Entra ID auth for ${var.project_name} chat (MSAL)"

  # "AzureADMyOrg" = only users in your Entra ID tenant can sign in.
  # No personal Microsoft accounts, no users from other organizations.
  sign_in_audience = "AzureADMyOrg"

  # Make the person running Terraform an owner of this app registration,
  # so they can update it in future terraform apply runs.
  owners = [data.azuread_client_config.current.object_id]

  # SPA platform configuration.
  # Unlike a Web app, a SPA does not use a client secret. Instead, MSAL uses
  # PKCE (Proof Key for Code Exchange) to securely exchange authorization codes
  # for tokens in the browser.
  #
  # The redirect URI is set separately (below) because it depends on the
  # Container App's hostname, which isn't known until the app is created.
  single_page_application {
    redirect_uris = []
  }

  # Allow Entra ID to issue ID tokens.
  # ID tokens identify who the user is (email, name, tenant).
  # The frontend sends this token to the backend in the Authorization header.
  web {
    implicit_grant {
      id_token_issuance_enabled = true
    }
  }

  # Terraform manages redirect URIs via a separate resource below.
  lifecycle {
    ignore_changes = [single_page_application[0].redirect_uris]
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
# MSAL handles this callback in the browser — your backend doesn't need to do anything.
#
# The type is "SPA" (not "Web") — this tells Entra ID to use PKCE instead of
# requiring a client secret.
#
# This is created as a separate resource (not inline on the app registration) because
# it depends on the Container App's hostname, which isn't known until the app is created.
resource "azuread_application_redirect_uris" "main" {
  application_id = azuread_application.main.id
  type           = "SPA"
  redirect_uris  = ["https://${azurerm_container_app.main.ingress[0].fqdn}"]
}
