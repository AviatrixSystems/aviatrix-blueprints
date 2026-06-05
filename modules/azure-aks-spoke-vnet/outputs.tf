output "resource_group_name" {
  description = "Resource group containing the spoke VNet."
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "Azure resource ID of the spoke VNet."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the spoke VNet."
  value       = azurerm_virtual_network.this.name
}

output "aviatrix_vpc_id" {
  description = "Aviatrix vpc_id form (vnet_name:rg:guid)."
  value       = format("%s:%s:%s", azurerm_virtual_network.this.name, azurerm_resource_group.this.name, azurerm_virtual_network.this.guid)
}

output "gateway_subnet_id" {
  description = "Subnet ID of the Aviatrix gateway subnet."
  value       = azurerm_subnet.gateway.id
}

output "ingress_subnet_id" {
  description = "Subnet ID of the ingress subnet (internal NGINX LB)."
  value       = azurerm_subnet.ingress.id
}

output "ingress_subnet_name" {
  description = "Name of the ingress subnet (used by Helm ingress-nginx annotations)."
  value       = azurerm_subnet.ingress.name
}

output "node_subnet_id" {
  description = "Subnet ID for AKS node VMs."
  value       = azurerm_subnet.node.id
}

output "pod_subnet_id" {
  description = "Subnet ID for AKS pods (pod-subnet mode)."
  value       = azurerm_subnet.pod.id
}

output "node_route_table_id" {
  description = "Node route table ID (Aviatrix programs 0/0 -> spoke GW here)."
  value       = azurerm_route_table.node.id
}

output "pod_route_table_id" {
  description = "Pod route table ID (Aviatrix programs 0/0 -> spoke GW here)."
  value       = azurerm_route_table.pod.id
}

output "spoke_gateway_name" {
  description = "Name of the Aviatrix spoke gateway."
  value       = module.spoke.spoke_gateway.gw_name
}

output "spoke_gateway_public_ip" {
  description = "Public IP of the spoke gateway (for AKS API authorized_ip_ranges)."
  value       = module.spoke.spoke_gateway.public_ip
}

output "spoke_gateway_private_ip" {
  description = "Private IP of the spoke gateway."
  value       = module.spoke.spoke_gateway.private_ip
  sensitive   = true
}

output "spoke_gateway" {
  description = "Full Aviatrix spoke gateway object."
  value       = module.spoke.spoke_gateway
  sensitive   = true
}
