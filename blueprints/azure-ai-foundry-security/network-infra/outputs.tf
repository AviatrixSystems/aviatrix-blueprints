output "resource_group_name" {
  description = "Name of the network infrastructure resource group (includes random suffix) — used by vpn-access as vnet_resource_group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_name_dns" {
  description = "Resource group where private DNS zones are deployed — used by foundry-playground as resource_group_name_dns"
  value       = azurerm_resource_group.main.name
}

output "subnet_id_agent" {
  description = "Resource ID of the ACA-delegated agent subnet — used by foundry-playground as subnet_id_agent"
  value       = azurerm_subnet.foundry_agent.id
}

output "subnet_id_private_endpoint" {
  description = "Resource ID of the private endpoint subnet — used by foundry-playground as subnet_id_private_endpoint"
  value       = azurerm_subnet.private_endpoint.id
}

output "subscription_id_infra" {
  description = "Subscription ID where network infrastructure is deployed — used by foundry-playground as subscription_id_infra"
  value       = var.subscription_id
}

output "subscription_id_resources" {
  description = "Subscription ID where network infrastructure is deployed — used by foundry-playground as subscription_id_resources if deploying in same subscription"
  value       = var.subscription_id
}

output "location" {
  description = "Azure region of the deployment — used by foundry-playground as location"
  value       = var.location
}

output "vnet_name" {
  description = "Name of the deployed foundry VNet — used by vpn-access as vnet_name"
  value       = azurerm_virtual_network.main.name
}

output "suffix" {
  description = "Random 4-digit suffix shared across this deployment — used by vpn-access as suffix"
  value       = local.suffix
}
