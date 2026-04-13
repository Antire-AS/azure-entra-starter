# Values you need after deployment.
#
# Run `terraform output` to see these, or reference specific ones:
#   terraform output url        → the app URL
#   terraform output tenant_id  → put this in staticwebapp.config.json
#   terraform output -raw api_key → deployment token for SWA CLI

output "url" {
  description = "The public URL of your chat app. Open this in a browser — you'll be redirected to Microsoft login."
  value       = "https://${azurerm_static_web_app.main.default_host_name}"
}

output "api_key" {
  description = "Deployment token for the SWA CLI. Use with: swa deploy --deployment-token <this value>"
  value       = azurerm_static_web_app.main.api_key
  sensitive   = true
}

output "tenant_id" {
  description = "Your Entra ID tenant ID. Replace <TENANT_ID> in frontend/staticwebapp.config.json with this value."
  value       = data.azuread_client_config.current.tenant_id
}

output "client_id" {
  description = "The Entra ID app registration client ID. You generally don't need this — it's set as an app setting automatically."
  value       = azuread_application.main.client_id
}
