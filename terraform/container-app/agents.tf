# Service-to-service access for AI agents and automated clients (optional).
#
# WHEN DO YOU NEED THIS?
#
#   If you have an AI agent, a backend service, a scheduled job, or any automated
#   process that needs to call your chat API — it can't sign in through a browser.
#   It needs its own identity and a way to authenticate programmatically.
#
#   Examples:
#     - An AI agent running in another Container App that calls /api/chat
#     - A Python script that sends messages to the chat API on a schedule
#     - A monitoring service that tests the chat endpoint
#     - Another team's application that integrates with your chat
#
# HOW IS THIS DIFFERENT FROM HUMAN ACCESS?
#
#   Humans:
#     Browser → redirect to Microsoft login → sign in → cookie → Easy Auth forwards
#     The user interacts with a login page. No code needed in your app.
#
#   Agents/services:
#     Code → acquire token via client credentials → send as Bearer header → Easy Auth validates
#     No browser, no login page. The agent uses a client ID + secret to get a token.
#
# HOW IT WORKS:
#
#   1. This file creates an "app role" on your chat app called "Agent.Access".
#      An app role is like a permission — it says "this type of access exists."
#
#   2. It creates a separate app registration for the agent — the agent's own identity.
#      This comes with a client ID and a client secret (like a username and password
#      for the service).
#
#   3. It assigns the Agent.Access role to the agent's identity. This tells Entra ID:
#      "this agent is allowed to call the chat API."
#
#   4. At runtime, the agent uses the OAuth2 client_credentials flow to get a token:
#
#        POST https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token
#        client_id=<agent-client-id>
#        client_secret=<agent-secret>
#        scope=api://<chat-app-client-id>/.default
#        grant_type=client_credentials
#
#   5. The agent sends the token in the Authorization header:
#
#        GET /api/chat
#        Authorization: Bearer <token>
#
#   6. Easy Auth (the reverse proxy on the Container App) validates the token:
#      - Is the token issued by our Entra ID tenant?
#      - Is the audience correct (api://<chat-app-client-id>)?
#      - Does the agent have the Agent.Access role?
#      If all checks pass, the request is forwarded to your app.
#
# HOW TO CONFIGURE A NEW AGENT:
#
#   This file creates one example agent. To add more agents, either:
#
#   a) Add more email addresses to access_group_members (if using groups) —
#      but agents aren't users, so this doesn't apply.
#
#   b) Create additional app registrations and role assignments following
#      the same pattern as below. Each agent gets its own client ID + secret.
#
#   c) If the agent runs on Azure (e.g. another Container App, Azure Function,
#      or VM), it can use a managed identity instead of a client secret.
#      In that case, you don't need an app registration for the agent —
#      just assign the Agent.Access role to the managed identity's principal ID:
#
#        resource "azuread_app_role_assignment" "other_service" {
#          app_role_id         = azuread_application.main.app_role[0].id
#          principal_object_id = <other-service-managed-identity-principal-id>
#          resource_object_id  = azuread_service_principal.main.object_id
#        }
#
# EXAMPLE: HOW AN AGENT CALLS THE API
#
#   Python:
#     import requests
#
#     # Step 1: Get a token
#     token_response = requests.post(
#         f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token",
#         data={
#             "client_id": agent_client_id,
#             "client_secret": agent_client_secret,
#             "scope": f"api://{chat_app_client_id}/.default",
#             "grant_type": "client_credentials",
#         },
#     )
#     token = token_response.json()["access_token"]
#
#     # Step 2: Call the chat API
#     response = requests.post(
#         "https://your-chat-app.azurecontainerapps.io/api/chat",
#         headers={"Authorization": f"Bearer {token}"},
#         json={"messages": [{"role": "user", "content": "Hello"}]},
#     )
#     print(response.text)
#
#   curl:
#     # Step 1: Get a token
#     TOKEN=$(curl -s -X POST \
#       "https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token" \
#       -d "client_id=<agent-client-id>" \
#       -d "client_secret=<agent-secret>" \
#       -d "scope=api://<chat-app-client-id>/.default" \
#       -d "grant_type=client_credentials" | jq -r '.access_token')
#
#     # Step 2: Call the chat API
#     curl -H "Authorization: Bearer $TOKEN" \
#       -H "Content-Type: application/json" \
#       -d '{"messages":[{"role":"user","content":"Hello"}]}' \
#       https://your-chat-app.azurecontainerapps.io/api/chat

# --- Variables ---

variable "create_agent_identity" {
  description = "Set to true to create an app registration for an AI agent or service that needs to call the chat API programmatically (no browser). See agents.tf for details."
  type        = bool
  default     = false
}

variable "agent_display_name" {
  description = "Display name for the agent's app registration in Entra ID (only used if create_agent_identity = true)."
  type        = string
  default     = "Chat Agent"
}

# --- App Role on the chat application ---
# This defines a permission called "Agent.Access" on your chat app.
# Agents must be assigned this role before they can call the API.
# The random UUID identifies this specific role — it must be unique
# within the app registration.

resource "random_uuid" "agent_role_id" {}

# The Agent.Access app role is defined as a dynamic block on the
# azuread_application resource in auth.tf. It's only added when
# create_agent_identity = true. The random_uuid below generates
# the role's unique ID.

# --- Agent App Registration ---
# The agent's own identity in Entra ID. This is separate from the chat app's
# identity — the agent is a "client" that calls the chat app's API.

resource "azuread_application" "agent" {
  count = var.create_agent_identity ? 1 : 0

  display_name     = "${var.agent_display_name} - ${var.project_name}-${var.environment}"
  description      = "Service identity for an agent that calls the ${var.project_name} chat API"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "agent" {
  count     = var.create_agent_identity ? 1 : 0
  client_id = azuread_application.agent[0].client_id
}

# The agent's client secret — this is the "password" the agent uses to
# authenticate. Store it securely (e.g. in Key Vault, environment variable,
# or a secrets manager). Rotate it periodically.
resource "azuread_application_password" "agent" {
  count          = var.create_agent_identity ? 1 : 0
  application_id = azuread_application.agent[0].id
  display_name   = "${var.agent_display_name}-secret"
}

# --- Assign the Agent.Access role to the agent ---
# This tells Entra ID: "this agent is allowed to call the chat API."
# Without this assignment, the agent can acquire a token but it won't
# contain the required role, and Easy Auth will reject the request.
resource "azuread_app_role_assignment" "agent_access" {
  count = var.create_agent_identity ? 1 : 0

  app_role_id         = random_uuid.agent_role_id.result
  principal_object_id = azuread_service_principal.agent[0].object_id
  resource_object_id  = azuread_service_principal.main.object_id
}

# --- Outputs ---

output "agent_client_id" {
  description = "The agent's client ID. The agent uses this to identify itself when requesting a token."
  value       = var.create_agent_identity ? azuread_application.agent[0].client_id : null
}

output "agent_client_secret" {
  description = "The agent's client secret. Store this securely — the agent uses it to authenticate. Rotate periodically."
  value       = var.create_agent_identity ? azuread_application_password.agent[0].value : null
  sensitive   = true
}

output "agent_token_scope" {
  description = "The scope the agent requests when acquiring a token. Use this in the client_credentials token request."
  value       = var.create_agent_identity ? "api://${azuread_application.main.client_id}/.default" : null
}

output "agent_token_endpoint" {
  description = "The OAuth2 token endpoint. The agent POSTs here to get an access token."
  value       = var.create_agent_identity ? "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/oauth2/v2.0/token" : null
}
