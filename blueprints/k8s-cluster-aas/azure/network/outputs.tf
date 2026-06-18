#####################
# Transit Gateway
#####################

output "transit_gateway_name" {
  description = "Aviatrix transit gateway name"
  value       = module.azure_transit.transit_gateway.gw_name
  sensitive   = true
}

output "transit_vnet_id" {
  description = "Transit VNet ID"
  value       = module.azure_transit.vpc.vpc_id
}

#####################
# Team-A VNet and Spoke
#####################

output "team_a_vnet_id" {
  description = "Team-A VNet ID (Aviatrix format: vnet_name:rg_name:guid)"
  value       = aviatrix_vpc.team_a.vpc_id
}

output "team_a_vnet_name" {
  description = "Team-A VNet name"
  value       = aviatrix_vpc.team_a.name
}

output "team_a_resource_group_name" {
  description = "Team-A resource group name (created by aviatrix_vpc)"
  value       = local.team_a_rg_name
}

output "team_a_arm_vnet_id" {
  description = "Team-A VNet ARM resource ID"
  value       = local.team_a_arm_vnet_id
}

output "team_a_public_subnets" {
  description = "Team-A VNet public subnets (created by aviatrix_vpc)"
  value       = aviatrix_vpc.team_a.public_subnets
}

# Backward-compatible outputs for downstream layers (clusters, nodes)
# aviatrix_vpc public_subnets[1] is used as the AKS node subnet
# (public_subnets[0] is reserved for the Aviatrix spoke gateway)
output "team_a_aks_system_subnet_id" {
  description = "Team-A AKS system node pool subnet ID"
  value       = aviatrix_vpc.team_a.public_subnets[1].subnet_id
}

output "team_a_aks_system_subnet_cidr" {
  description = "Team-A AKS system node pool subnet CIDR"
  value       = aviatrix_vpc.team_a.public_subnets[1].cidr
}

output "team_a_aks_system_subnet_name" {
  description = "Team-A AKS system node pool subnet name"
  value       = aviatrix_vpc.team_a.public_subnets[1].name
}

output "team_a_spoke_gateway_name" {
  description = "Team-A spoke gateway name"
  value       = aviatrix_spoke_gateway.team_a.gw_name
  sensitive   = true
}

#####################
# Team-B VNet and Spoke
#####################

output "team_b_vnet_id" {
  description = "Team-B VNet ID (Aviatrix format: vnet_name:rg_name:guid)"
  value       = aviatrix_vpc.team_b.vpc_id
}

output "team_b_vnet_name" {
  description = "Team-B VNet name"
  value       = aviatrix_vpc.team_b.name
}

output "team_b_resource_group_name" {
  description = "Team-B resource group name (created by aviatrix_vpc)"
  value       = element(split(":", aviatrix_vpc.team_b.vpc_id), 1)
}

output "team_b_arm_vnet_id" {
  description = "Team-B VNet ARM resource ID"
  value       = local.team_b_arm_vnet_id
}

output "team_b_public_subnets" {
  description = "Team-B VNet public subnets (created by aviatrix_vpc)"
  value       = aviatrix_vpc.team_b.public_subnets
}

output "team_b_aks_system_subnet_id" {
  description = "Team-B AKS system node pool subnet ID"
  value       = aviatrix_vpc.team_b.public_subnets[1].subnet_id
}

output "team_b_aks_system_subnet_cidr" {
  description = "Team-B AKS system node pool subnet CIDR"
  value       = aviatrix_vpc.team_b.public_subnets[1].cidr
}

output "team_b_aks_system_subnet_name" {
  description = "Team-B AKS system node pool subnet name"
  value       = aviatrix_vpc.team_b.public_subnets[1].name
}

output "team_b_spoke_gateway_name" {
  description = "Team-B spoke gateway name"
  value       = aviatrix_spoke_gateway.team_b.gw_name
  sensitive   = true
}

#####################
# Team-C VNet and Spoke
#####################

output "team_c_vnet_id" {
  description = "Team-C VNet ID (Aviatrix format: vnet_name:rg_name:guid)"
  value       = aviatrix_vpc.team_c.vpc_id
}

output "team_c_vnet_name" {
  description = "Team-C VNet name"
  value       = aviatrix_vpc.team_c.name
}

output "team_c_resource_group_name" {
  description = "Team-C resource group name (created by aviatrix_vpc)"
  value       = element(split(":", aviatrix_vpc.team_c.vpc_id), 1)
}

output "team_c_arm_vnet_id" {
  description = "Team-C VNet ARM resource ID"
  value       = local.team_c_arm_vnet_id
}

output "team_c_public_subnets" {
  description = "Team-C VNet public subnets (created by aviatrix_vpc)"
  value       = aviatrix_vpc.team_c.public_subnets
}

output "team_c_aks_system_subnet_id" {
  description = "Team-C AKS system node pool subnet ID"
  value       = aviatrix_vpc.team_c.public_subnets[1].subnet_id
}

output "team_c_aks_system_subnet_cidr" {
  description = "Team-C AKS system node pool subnet CIDR"
  value       = aviatrix_vpc.team_c.public_subnets[1].cidr
}

output "team_c_aks_system_subnet_name" {
  description = "Team-C AKS system node pool subnet name"
  value       = aviatrix_vpc.team_c.public_subnets[1].name
}

output "team_c_spoke_gateway_name" {
  description = "Team-C spoke gateway name"
  value       = aviatrix_spoke_gateway.team_c.gw_name
  sensitive   = true
}

#####################
# Database Spoke
#####################

output "db_vnet_id" {
  value = module.spoke_db.vpc.vpc_id
}

output "db_private_ip" {
  value = var.db_private_ip
}

output "db_dns_name" {
  value = "db.${var.private_dns_zone_name}"
}

#####################
# Azure Private DNS
#####################

output "private_dns_zone_id" {
  value = azurerm_private_dns_zone.this.id
}

output "private_dns_zone_name" {
  value = azurerm_private_dns_zone.this.name
}

output "private_dns_zone_resource_group" {
  value = local.team_a_rg_name
}

#####################
# Cluster Names
#####################

output "name_prefix" {
  value = local.name_prefix
}

output "team_a_cluster_name" {
  value = "${local.name_prefix}-team-a"
}

output "team_b_cluster_name" {
  value = "${local.name_prefix}-team-b"
}

output "team_c_cluster_name" {
  value = "${local.name_prefix}-team-c"
}

#####################
# Shared Configuration
#####################

output "azure_region" {
  value = var.azure_region
}

output "azure_subscription_id" {
  value     = var.azure_subscription_id
  sensitive = true
}

output "pod_cidr" {
  value = local.pod_cidr
}
