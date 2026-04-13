# Entra ID authentication for Static Web App.
#
# This file registers your app with Microsoft Entra ID (formerly Azure AD)
# so that users can sign in with their organization accounts.
#
# HOW IT WORKS:
#   When someone visits your app, Static Web Apps checks if they're signed in.
#   If not, they're redirected to Microsoft's login page. After signing in,
#   they're sent back to your app with a session cookie. Your app code never
#   handles tokens or passwords — the platform does it all.
#
#   For this to work, Microsoft needs to know your app exists. That's what
#   an "app registration" is — it's your app's identity in Entra ID.
#   This file creates that identity automatically.
#
# WHO CAN SIGN IN?
#   By default (create_access_group = false): everyone in your Entra ID tenant.
#   With a group (create_access_group = true): only members of that group.
#   See groups.tf for how group-based access works.
#
# WHY A CLIENT SECRET?
#   Static Web Apps uses the authorization code flow, which requires a client
#   secret. This is different from Container Apps (which uses implicit flow
#   and doesn't need a secret). The secret is stored as an app setting on the
#   SWA and never appears in your app code.
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

# --- Client Secret ---
# Static Web Apps needs a client secret to complete the OAuth flow.
# This is stored as an app setting (AZURE_CLIENT_SECRET) on the SWA resource
# in main.tf — it's never exposed to your application code.
resource "azuread_application_password" "main" {
  application_id = azuread_application.main.id
  display_name   = "${var.project_name}-${var.environment}-secret"
}

# --- Redirect URI ---
# After the user signs in at Microsoft, their browser is redirected back to this URL.
# Easy Auth handles this callback automatically — your code doesn't need to do anything.
#
# This is created as a separate resource (not inline on the app registration) because
# it depends on the SWA hostname, which isn't known until the SWA is created.
resource "azuread_application_redirect_uris" "main" {
  application_id = azuread_application.main.id
  type           = "Web"
  redirect_uris  = ["https://${azurerm_static_web_app.main.default_host_name}/.auth/login/aad/callback"]
}
