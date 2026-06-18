# -----------------------------------------------------------------------------
# Pattern C: Prod/Non-Prod + Namespace-as-a-Service — GCP Network Outputs
# -----------------------------------------------------------------------------

output "transit_gw_name" {
  description = "Aviatrix Transit Gateway name"
  value       = aviatrix_transit_gateway.main.gw_name
}

output "prod_vpc_id" {
  description = "Production VPC ID (Aviatrix format / GCP self-link)"
  value       = aviatrix_vpc.prod.vpc_id
}

output "prod_vpc_name" {
  description = "Production VPC name"
  value       = aviatrix_vpc.prod.name
}

output "nonprod_vpc_id" {
  description = "Non-production VPC ID (Aviatrix format / GCP self-link)"
  value       = aviatrix_vpc.nonprod.vpc_id
}

output "nonprod_vpc_name" {
  description = "Non-production VPC name"
  value       = aviatrix_vpc.nonprod.name
}

output "db_vpc_id" {
  description = "Database spoke VPC ID"
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

output "transit_vpc_self_link" {
  description = "Transit VPC self-link for Cloud DNS network_url"
  value       = aviatrix_vpc.transit.vpc_id
}

output "dns_zone_name" {
  description = "Cloud DNS private zone name"
  value       = google_dns_managed_zone.internal.name
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
