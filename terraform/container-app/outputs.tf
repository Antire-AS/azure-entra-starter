# Values you need after deployment.
#
# Run `terraform output` to see these, or reference specific ones:
#   terraform output url               → the app URL
#   terraform output container_registry → where to push Docker images
#   terraform output key_vault_name     → where to store secrets

output "url" {
  description = "The public URL of your chat app. Open this in a browser — you'll be redirected to Microsoft login."
  value       = "https://${azurerm_container_app.main.ingress[0].fqdn}"
}

output "container_registry" {
  description = "The container registry address. Push your Docker image here: docker push <registry>/<project>:latest"
  value       = azurerm_container_registry.main.login_server
}

output "client_id" {
  description = "The Entra ID app registration client ID. You generally don't need this — it's used internally by Easy Auth."
  value       = azuread_application.main.client_id
}

output "key_vault_name" {
  description = "The Key Vault name. Store your OpenAI API key here: az keyvault secret set --vault-name <name> --name azure-openai-api-key --value <key>"
  value       = azurerm_key_vault.main.name
}
