locals {
  tags = {
    blueprint = "secured-ai-foundry"
  }

  # sourced from network-infra remote state
  suffix                     = data.terraform_remote_state.network.outputs.suffix
  location                   = data.terraform_remote_state.network.outputs.location
  resource_group_name_dns    = data.terraform_remote_state.network.outputs.resource_group_name_dns
  subnet_id_agent            = data.terraform_remote_state.network.outputs.subnet_id_agent
  subnet_id_private_endpoint = data.terraform_remote_state.network.outputs.subnet_id_private_endpoint

  project_id_guid = "${substr(azapi_resource.ai_foundry_project.output.properties.internalId, 0, 8)}-${substr(azapi_resource.ai_foundry_project.output.properties.internalId, 8, 4)}-${substr(azapi_resource.ai_foundry_project.output.properties.internalId, 12, 4)}-${substr(azapi_resource.ai_foundry_project.output.properties.internalId, 16, 4)}-${substr(azapi_resource.ai_foundry_project.output.properties.internalId, 20, 12)}"

  foundry_user_oid = coalesce(var.foundry_user_principal_id, data.azurerm_client_config.current.object_id)
}

# ── Provider variables (cannot be sourced from remote state) ─────────────────

variable "subscription_id_infra" {
  description = "Subscription ID where network infrastructure is deployed"
  type        = string
}

variable "subscription_id_resources" {
  description = "Subscription ID where Foundry resources will be deployed"
  type        = string
}

variable "foundry_user_principal_id" {
  description = "Object ID of the user or service principal to assign Foundry User role on the project. Defaults to the deploying identity."
  type        = string
  default     = null
}
