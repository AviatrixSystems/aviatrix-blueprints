output "vnet_id" {
  description = "Azure resource ID of the VNet"
  value       = azurerm_virtual_network.vnet.id
}

output "vnet_name" {
  description = "Name of the VNet"
  value       = azurerm_virtual_network.vnet.name
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.vnet.name
}

output "resource_group_id" {
  description = "Azure resource ID of the resource group"
  value       = azurerm_resource_group.vnet.id
}

# Aviatrix-specific VNet ID format: "VNet_name:Resource_Group_name"
output "aviatrix_vpc_id" {
  description = "VNet ID in Aviatrix format for use_existing_vpc (VNet_name:RG_name)"
  value       = "${azurerm_virtual_network.vnet.name}:${azurerm_resource_group.vnet.name}"
}

output "avx_gateway_subnet_cidr" {
  description = "CIDR of the Aviatrix gateway subnet"
  value       = azurerm_subnet.avx_gw.address_prefixes[0]
}

output "avx_gateway_subnet_id" {
  description = "Azure resource ID of the Aviatrix gateway subnet"
  value       = azurerm_subnet.avx_gw.id
}

output "nodes_subnet_id" {
  description = "Azure resource ID of the AKS nodes subnet"
  value       = azurerm_subnet.nodes.id
}

output "nodes_subnet_cidr" {
  description = "CIDR of the AKS nodes subnet"
  value       = azurerm_subnet.nodes.address_prefixes[0]
}

output "system_subnet_id" {
  description = "Azure resource ID of the system/ingress subnet"
  value       = azurerm_subnet.system.id
}

output "system_subnet_cidr" {
  description = "CIDR of the system/ingress subnet"
  value       = azurerm_subnet.system.address_prefixes[0]
}

output "vnet_cidr" {
  description = "Primary (routable) CIDR of the VNet"
  value       = tolist(azurerm_virtual_network.vnet.address_space)[0]
}

output "pod_subnet_id" {
  description = "Azure resource ID of the pod subnet (used by AKS pod-subnet mode)"
  value       = azurerm_subnet.pods.id
}

output "pod_subnet_cidr" {
  description = "CIDR of the pod subnet (matches var.pod_cidr)"
  value       = azurerm_subnet.pods.address_prefixes[0]
}
