#####################
# Transit
#####################

output "transit_gateway_name" {
  description = "Aviatrix transit gateway name"
  value       = nonsensitive(module.azure_transit.transit_gateway.gw_name)
}

output "transit_vnet_id" {
  description = "Transit VNet ID"
  value       = nonsensitive(module.azure_transit.vpc.id)
}

#####################
# Frontend
#####################

output "frontend_vnet_id" {
  description = "Frontend VNet Azure resource ID"
  value       = module.frontend_vnet.vnet_id
}

output "frontend_vnet_name" {
  description = "Frontend VNet name"
  value       = module.frontend_vnet.vnet_name
}

output "frontend_resource_group_name" {
  description = "Frontend resource group name"
  value       = module.frontend_vnet.resource_group_name
}

output "frontend_resource_group_id" {
  description = "Frontend resource group Azure resource ID"
  value       = module.frontend_vnet.resource_group_id
}

output "frontend_nodes_subnet_id" {
  description = "Frontend AKS nodes subnet ID (has UDR → Aviatrix GW pre-associated)"
  value       = module.frontend_vnet.nodes_subnet_id
}

output "frontend_nodes_subnet_cidr" {
  description = "Frontend AKS nodes subnet CIDR"
  value       = module.frontend_vnet.nodes_subnet_cidr
}

output "frontend_pod_subnet_id" {
  description = "Frontend pod subnet ID — passed to AKS for pod-subnet mode (NOT overlay)"
  value       = module.frontend_vnet.pod_subnet_id
}

output "frontend_pod_subnet_cidr" {
  description = "Frontend pod subnet CIDR (matches var.pod_cidr)"
  value       = module.frontend_vnet.pod_subnet_cidr
}

output "frontend_system_subnet_id" {
  description = "Frontend system/ingress subnet ID"
  value       = module.frontend_vnet.system_subnet_id
}

output "frontend_system_subnet_cidr" {
  description = "Frontend system/ingress subnet CIDR"
  value       = module.frontend_vnet.system_subnet_cidr
}

output "frontend_spoke_gateway_name" {
  description = "Frontend Aviatrix spoke gateway name"
  value       = nonsensitive(module.frontend_spoke.spoke_gateway.gw_name)
}

output "frontend_spoke_gateway_private_ip" {
  description = "Frontend Aviatrix spoke gateway private IP"
  value       = nonsensitive(module.frontend_spoke.spoke_gateway.private_ip)
}

output "frontend_spoke_gateway_public_ip" {
  description = "Frontend Aviatrix spoke gateway public IP (egress NAT for AKS nodes — must be in AKS authorized_ip_ranges)"
  value       = nonsensitive(module.frontend_spoke.spoke_gateway.public_ip)
}

output "frontend_route_table_id" {
  description = "Frontend UDR route table ID (for AKS identity role assignment)"
  value       = azurerm_route_table.frontend_udr.id
}

output "frontend_cluster_name" {
  description = "Expected AKS cluster name for the frontend cluster"
  value       = local.clusters.frontend.name
}

#####################
# Backend
#####################

output "backend_vnet_id" {
  description = "Backend VNet Azure resource ID"
  value       = module.backend_vnet.vnet_id
}

output "backend_vnet_name" {
  description = "Backend VNet name"
  value       = module.backend_vnet.vnet_name
}

output "backend_resource_group_name" {
  description = "Backend resource group name"
  value       = module.backend_vnet.resource_group_name
}

output "backend_resource_group_id" {
  description = "Backend resource group Azure resource ID"
  value       = module.backend_vnet.resource_group_id
}

output "backend_nodes_subnet_id" {
  description = "Backend AKS nodes subnet ID (has UDR → Aviatrix GW pre-associated)"
  value       = module.backend_vnet.nodes_subnet_id
}

output "backend_nodes_subnet_cidr" {
  description = "Backend AKS nodes subnet CIDR"
  value       = module.backend_vnet.nodes_subnet_cidr
}

output "backend_pod_subnet_id" {
  description = "Backend pod subnet ID — passed to AKS for pod-subnet mode (NOT overlay)"
  value       = module.backend_vnet.pod_subnet_id
}

output "backend_pod_subnet_cidr" {
  description = "Backend pod subnet CIDR (matches var.pod_cidr)"
  value       = module.backend_vnet.pod_subnet_cidr
}

output "backend_system_subnet_id" {
  description = "Backend system/ingress subnet ID"
  value       = module.backend_vnet.system_subnet_id
}

output "backend_system_subnet_cidr" {
  description = "Backend system/ingress subnet CIDR"
  value       = module.backend_vnet.system_subnet_cidr
}

output "backend_spoke_gateway_name" {
  description = "Backend Aviatrix spoke gateway name"
  value       = nonsensitive(module.backend_spoke.spoke_gateway.gw_name)
}

output "backend_spoke_gateway_private_ip" {
  description = "Backend Aviatrix spoke gateway private IP"
  value       = nonsensitive(module.backend_spoke.spoke_gateway.private_ip)
}

output "backend_spoke_gateway_public_ip" {
  description = "Backend Aviatrix spoke gateway public IP (egress NAT for AKS nodes — must be in AKS authorized_ip_ranges)"
  value       = nonsensitive(module.backend_spoke.spoke_gateway.public_ip)
}

output "backend_route_table_id" {
  description = "Backend UDR route table ID (for AKS identity role assignment)"
  value       = azurerm_route_table.backend_udr.id
}

output "backend_cluster_name" {
  description = "Expected AKS cluster name for the backend cluster"
  value       = local.clusters.backend.name
}

#####################
# DB
#####################

output "db_vnet_id" {
  description = "DB VNet Azure resource ID"
  value       = azurerm_virtual_network.db.id
}

output "db_resource_group_name" {
  description = "DB resource group name"
  value       = azurerm_resource_group.db.name
}

output "db_vm_private_ip" {
  description = "DB test VM private IP"
  value       = module.db_vm.vm_private_ip
}

output "db_vm_name" {
  description = "DB test VM name"
  value       = module.db_vm.vm_name
}

#####################
# DNS
#####################

output "private_dns_zone_name" {
  description = "Azure Private DNS zone name"
  value       = azurerm_private_dns_zone.main.name
}

output "private_dns_zone_id" {
  description = "Azure Private DNS zone resource ID"
  value       = azurerm_private_dns_zone.main.id
}

output "dns_resource_group_name" {
  description = "Resource group containing the private DNS zone"
  value       = azurerm_resource_group.shared.name
}

#####################
# Common
#####################

output "pod_cidr" {
  description = "Cilium overlay pod CIDR (same across all clusters)"
  value       = var.pod_cidr
}

output "service_cidr" {
  description = "Kubernetes service CIDR"
  value       = var.service_cidr
}

output "dns_service_ip" {
  description = "Kubernetes DNS service IP"
  value       = var.dns_service_ip
}

output "azure_region" {
  description = "Azure region (azurerm format)"
  value       = var.azure_region
}

output "name_prefix" {
  description = "Resource name prefix"
  value       = var.name_prefix
}

#####################
# Application Gateways
#####################

output "frontend_appgw_public_ip" {
  description = "Public IP of the frontend Application Gateway (internet-facing Gatus access)"
  value       = azurerm_public_ip.frontend_appgw.ip_address
}

output "backend_appgw_public_ip" {
  description = "Public IP of the backend Application Gateway (internet-facing Gatus access)"
  value       = azurerm_public_ip.backend_appgw.ip_address
}

output "frontend_nginx_lb_ip" {
  description = "Static private IP for the frontend NGINX internal load balancer"
  value       = local.frontend_nginx_lb_ip
}

output "backend_nginx_lb_ip" {
  description = "Static private IP for the backend NGINX internal load balancer"
  value       = local.backend_nginx_lb_ip
}
