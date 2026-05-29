#####################
# Transit Gateway
#####################

output "transit_gateway_name" {
  description = "Aviatrix transit gateway name"
  value       = module.gcp_transit.transit_gateway.gw_name
  sensitive   = true
}

#####################
# Team-A VPC and Spoke
#####################

output "team_a_network_name" {
  description = "Team-A VPC network name"
  value       = module.team_a_vpc.vpc_name
}

output "team_a_network_id" {
  description = "Team-A VPC network resource ID"
  value       = module.team_a_vpc.vpc_id
}

output "team_a_network_self_link" {
  description = "Team-A VPC network self-link URL"
  value       = module.team_a_vpc.vpc_self_link
}

output "team_a_gke_nodes_subnet_name" {
  description = "Team-A GKE node pool subnet name"
  value       = module.team_a_vpc.nodes_subnet_name
}

output "team_a_gke_nodes_subnet_cidr" {
  description = "Team-A GKE node pool subnet CIDR"
  value       = local.teams["team-a"].nodes_cidr
}

output "team_a_pod_range_name" {
  description = "Team-A secondary range name for pod IPs"
  value       = module.team_a_vpc.pods_range_name
}

output "team_a_services_range_name" {
  description = "Team-A secondary range name for service IPs"
  value       = module.team_a_vpc.services_range_name
}

output "team_a_spoke_gateway_name" {
  description = "Team-A Aviatrix spoke gateway name"
  value       = module.team_a_spoke.spoke_gateway.gw_name
  sensitive   = true
}

#####################
# Team-B VPC and Spoke
#####################

output "team_b_network_name" {
  description = "Team-B VPC network name"
  value       = module.team_b_vpc.vpc_name
}

output "team_b_network_id" {
  description = "Team-B VPC network resource ID"
  value       = module.team_b_vpc.vpc_id
}

output "team_b_gke_nodes_subnet_name" {
  description = "Team-B GKE node pool subnet name"
  value       = module.team_b_vpc.nodes_subnet_name
}

output "team_b_gke_nodes_subnet_cidr" {
  description = "Team-B GKE node pool subnet CIDR"
  value       = local.teams["team-b"].nodes_cidr
}

output "team_b_pod_range_name" {
  description = "Team-B secondary range name for pod IPs"
  value       = module.team_b_vpc.pods_range_name
}

output "team_b_services_range_name" {
  description = "Team-B secondary range name for service IPs"
  value       = module.team_b_vpc.services_range_name
}

output "team_b_spoke_gateway_name" {
  description = "Team-B Aviatrix spoke gateway name"
  value       = module.team_b_spoke.spoke_gateway.gw_name
  sensitive   = true
}

#####################
# Team-C VPC and Spoke
#####################

output "team_c_network_name" {
  description = "Team-C VPC network name"
  value       = module.team_c_vpc.vpc_name
}

output "team_c_network_id" {
  description = "Team-C VPC network resource ID"
  value       = module.team_c_vpc.vpc_id
}

output "team_c_gke_nodes_subnet_name" {
  description = "Team-C GKE node pool subnet name"
  value       = module.team_c_vpc.nodes_subnet_name
}

output "team_c_gke_nodes_subnet_cidr" {
  description = "Team-C GKE node pool subnet CIDR"
  value       = local.teams["team-c"].nodes_cidr
}

output "team_c_pod_range_name" {
  description = "Team-C secondary range name for pod IPs"
  value       = module.team_c_vpc.pods_range_name
}

output "team_c_services_range_name" {
  description = "Team-C secondary range name for service IPs"
  value       = module.team_c_vpc.services_range_name
}

output "team_c_spoke_gateway_name" {
  description = "Team-C Aviatrix spoke gateway name"
  value       = module.team_c_spoke.spoke_gateway.gw_name
  sensitive   = true
}

#####################
# Database Spoke
#####################

output "db_vpc_name" {
  description = "Database spoke VPC name"
  value       = module.spoke_db.vpc.name
}

output "db_dns_name" {
  description = "Database DNS name"
  value       = "db.${var.dns_private_zone_name}"
}

#####################
# Cloud DNS
#####################

output "dns_zone_name" {
  description = "Cloud DNS managed zone name (resource name)"
  value       = google_dns_managed_zone.private.name
}

output "dns_zone_dns_name" {
  description = "Cloud DNS managed zone DNS name (FQDN)"
  value       = var.dns_private_zone_name
}

#####################
# Cluster Names
#####################

output "name_prefix" {
  description = "Name prefix used for all resources"
  value       = local.name_prefix
}

output "team_a_cluster_name" {
  description = "Team-A GKE cluster name"
  value       = local.teams["team-a"].name
}

output "team_b_cluster_name" {
  description = "Team-B GKE cluster name"
  value       = local.teams["team-b"].name
}

output "team_c_cluster_name" {
  description = "Team-C GKE cluster name"
  value       = local.teams["team-c"].name
}

#####################
# Master CIDRs
#####################

output "team_a_master_cidr" {
  description = "Team-A GKE control plane private CIDR block"
  value       = var.team_a_master_cidr
}

output "team_b_master_cidr" {
  description = "Team-B GKE control plane private CIDR block"
  value       = var.team_b_master_cidr
}

output "team_c_master_cidr" {
  description = "Team-C GKE control plane private CIDR block"
  value       = var.team_c_master_cidr
}

#####################
# Shared Configuration
#####################

output "gcp_region" {
  description = "GCP region for all resources"
  value       = var.gcp_region
}

output "gcp_project" {
  description = "GCP project ID"
  value       = var.gcp_project
}

output "pod_cidr" {
  description = "Overlay CIDR for pod networking (overlapping across VPCs)"
  value       = local.pod_cidr
}

output "services_cidr" {
  description = "Overlay CIDR for Kubernetes service IPs (overlapping across VPCs)"
  value       = local.services_cidr
}
