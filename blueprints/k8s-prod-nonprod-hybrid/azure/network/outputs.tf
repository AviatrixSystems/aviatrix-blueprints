# -----------------------------------------------------------------------------
# Pattern C: Prod/Non-Prod + Namespace-as-a-Service — Azure Network Outputs
# -----------------------------------------------------------------------------

output "transit_gw_name" {
  description = "Aviatrix Transit Gateway name"
  value       = aviatrix_transit_gateway.main.gw_name
}

output "prod_vnet_id" {
  description = "Production VNet ID (Aviatrix format)"
  value       = aviatrix_vpc.prod.vpc_id
}

output "prod_vnet_name" {
  description = "Production VNet name"
  value       = aviatrix_vpc.prod.name
}

output "prod_arm_vnet_id" {
  description = "Production VNet ARM resource ID"
  value       = local.prod_arm_vnet_id
}

output "nonprod_vnet_id" {
  description = "Non-production VNet ID (Aviatrix format)"
  value       = aviatrix_vpc.nonprod.vpc_id
}

output "nonprod_vnet_name" {
  description = "Non-production VNet name"
  value       = aviatrix_vpc.nonprod.name
}

output "nonprod_arm_vnet_id" {
  description = "Non-production VNet ARM resource ID"
  value       = local.nonprod_arm_vnet_id
}

output "db_vnet_id" {
  description = "Database spoke VNet ID (Aviatrix format)"
  value       = aviatrix_vpc.db.vpc_id
}

output "prod_spoke_gw_name" {
  description = "Production spoke gateway name"
  value       = aviatrix_spoke_gateway.prod.gw_name
}

output "nonprod_spoke_gw_name" {
  description = "Non-production spoke gateway name"
  value       = aviatrix_spoke_gateway.nonprod.gw_name
}

output "db_spoke_gw_name" {
  description = "Database spoke gateway name"
  value       = aviatrix_spoke_gateway.db.gw_name
}

output "private_dns_zone_name" {
  description = "Azure Private DNS zone name"
  value       = azurerm_private_dns_zone.internal.name
}

output "private_dns_zone_id" {
  description = "Azure Private DNS zone resource ID"
  value       = azurerm_private_dns_zone.internal.id
}

# SmartGroup UUIDs for cross-module references
output "sg_prod_vpc_uuid" {
  value = aviatrix_smart_group.prod_vpc.uuid
}

output "sg_nonprod_vpc_uuid" {
  value = aviatrix_smart_group.nonprod_vpc.uuid
}

output "sg_prod_db_uuid" {
  value = aviatrix_smart_group.prod_db.uuid
}

output "name_prefix" {
  description = "Name prefix with random suffix"
  value       = local.name_prefix
}
