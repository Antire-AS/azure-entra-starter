# Input variables for the Container App deployment.
#
# Pass these with -var flags or create a terraform.tfvars file:
#   resource_group_name   = "rg-my-chat"
#   project_name          = "my-chat"
#   azure_openai_endpoint = "https://my-openai.openai.azure.com"
#   ...
#
# Note: the OpenAI API key is NOT a Terraform variable. It's stored in Key Vault
# after the first apply (see main.tf for instructions).

variable "resource_group_name" {
  description = "Name of the pre-existing Azure resource group. Must already exist in your subscription."
  type        = string
}

variable "project_name" {
  description = "Project name, used to name all Azure resources (e.g. ca-<name>-dev, kv-<name>-dev). Keep it short, lowercase, no spaces."
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. dev, prod). Appended to resource names to avoid conflicts between environments."
  type        = string
  default     = "dev"
}

variable "azure_openai_endpoint" {
  description = "Endpoint URL for your Azure OpenAI resource (e.g. https://my-openai.openai.azure.com). Find it in Portal: Azure OpenAI -> Keys and Endpoint."
  type        = string
}

variable "azure_openai_deployment" {
  description = "Name of your Azure OpenAI model deployment (e.g. gpt-4o, gpt-4o-mini). This is the deployment name you chose when deploying the model, not the model name itself."
  type        = string
  default     = "gpt-4o"
}

variable "system_prompt" {
  description = "System prompt sent to the LLM with every chat request. Defines the assistant's behavior and personality."
  type        = string
  default     = "You are a helpful assistant."
}
