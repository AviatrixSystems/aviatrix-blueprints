output "acr_name" {
  description = "Azure Container Registry name"
  value       = azurerm_container_registry.acr.name
}

output "acr_login_server" {
  description = "ACR login server (FQDN)"
  value       = azurerm_container_registry.acr.login_server
}

output "ai_foundry_account_name" {
  description = "AI Foundry hub account name"
  value       = azapi_resource.ai_foundry.name
}

output "subscription_id" {
  description = "Subscription ID"
  value       = var.subscription_id_resources
}

output "resource_group_name" {
  description = "Name of the Foundry resource group (includes random suffix)"
  value       = azurerm_resource_group.main.name
}

output "ai_foundry_project_name" {
  description = "Name of the deployed Azure AI Foundry project"
  value       = azapi_resource.ai_foundry_project.name
}

output "hosts_file_entries" {
  description = "Add these lines to /etc/hosts (or Windows hosts file) to reach Foundry services without a private DNS resolver"
  value = join("\n", concat(
    [
      "${azurerm_private_endpoint.pe_storage.private_service_connection[0].private_ip_address} ${azurerm_storage_account.storage_account.name}.blob.core.windows.net",
      "${azurerm_private_endpoint.pe_cosmosdb.private_service_connection[0].private_ip_address} ${azurerm_cosmosdb_account.cosmosdb.name}.documents.azure.com",
      "${azurerm_private_endpoint.pe_aisearch.private_service_connection[0].private_ip_address} ${azapi_resource.ai_search.name}.search.windows.net",
    ],
    # AIServices PE allocates one IP per DNS zone — use private_dns_zone_configs to get the correct IP per zone
    [for cfg in azurerm_private_endpoint.pe_aifoundry.private_dns_zone_configs :
      "${cfg.record_sets[0].ip_addresses[0]} ${azapi_resource.ai_foundry.name}.${
        endswith(cfg.private_dns_zone_id, "privatelink.cognitiveservices.azure.com") ? "cognitiveservices.azure.com" :
        endswith(cfg.private_dns_zone_id, "privatelink.openai.azure.com") ? "openai.azure.com" :
        "services.ai.azure.com"
      }"
    ]
  ))
}
