# Values you need after deployment.
#
# Run `terraform output` to see these, or reference specific ones:
#   terraform output url                → the app URL
#   terraform output container_registry → where to push Docker images
#   terraform output client_id          → put this in frontend/index.html
#   terraform output tenant_id          → put this in frontend/index.html
#   terraform output key_vault_name     → where to store secrets

output "url" {
  description = "The public URL of your chat app. Open this in a browser — you'll see the MSAL sign-in page."
  value       = "https://${azurerm_container_app.main.ingress[0].fqdn}"
}

output "container_registry" {
  description = "The container registry address. Push your Docker image here: docker push <registry>/<project>:latest"
  value       = azurerm_container_registry.main.login_server
}

output "client_id" {
  description = "The Entra ID app registration client ID. Put this in the frontend index.html (replace __CLIENT_ID__)."
  value       = azuread_application.main.client_id
}

output "tenant_id" {
  description = "Your Entra ID tenant ID. Put this in the frontend index.html (replace __TENANT_ID__)."
  value       = data.azuread_client_config.current.tenant_id
}

output "key_vault_name" {
  description = "The Key Vault name. Store your OpenAI API key here: az keyvault secret set --vault-name <name> --name azure-openai-api-key --value <key>"
  value       = azurerm_key_vault.main.name
}
