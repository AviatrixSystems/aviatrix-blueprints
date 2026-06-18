#####################
# Transit Gateway
#####################

output "transit_gateway_name" {
  value     = module.gcp_transit.transit_gateway.gw_name
  sensitive = true
}

#####################
# Team-A VPC and Spoke
#####################

output "team_a_network_name" {
  value = module.team_a_vpc.network_name
}

output "team_a_network_id" {
  value = module.team_a_vpc.network_id
}

output "team_a_network_self_link" {
  value = module.team_a_vpc.network_self_link
}

output "team_a_gke_nodes_subnet_name" {
  value = module.team_a_vpc.gke_nodes_subnet_name
}

output "team_a_gke_nodes_subnet_cidr" {
  value = module.team_a_vpc.gke_nodes_subnet_cidr
}

output "team_a_pod_range_name" {
  value = module.team_a_vpc.pod_range_name
}

output "team_a_services_range_name" {
  value = module.team_a_vpc.services_range_name
}

output "team_a_spoke_gateway_name" {
  value     = module.team_a_spoke.spoke_gateway.gw_name
  sensitive = true
}

#####################
# Team-B VPC and Spoke
#####################

output "team_b_network_name" {
  value = module.team_b_vpc.network_name
}

output "team_b_network_id" {
  value = module.team_b_vpc.network_id
}

output "team_b_gke_nodes_subnet_name" {
  value = module.team_b_vpc.gke_nodes_subnet_name
}

output "team_b_gke_nodes_subnet_cidr" {
  value = module.team_b_vpc.gke_nodes_subnet_cidr
}

output "team_b_pod_range_name" {
  value = module.team_b_vpc.pod_range_name
}

output "team_b_services_range_name" {
  value = module.team_b_vpc.services_range_name
}

output "team_b_spoke_gateway_name" {
  value     = module.team_b_spoke.spoke_gateway.gw_name
  sensitive = true
}

#####################
# Team-C VPC and Spoke
#####################

output "team_c_network_name" {
  value = module.team_c_vpc.network_name
}

output "team_c_network_id" {
  value = module.team_c_vpc.network_id
}

output "team_c_gke_nodes_subnet_name" {
  value = module.team_c_vpc.gke_nodes_subnet_name
}

output "team_c_gke_nodes_subnet_cidr" {
  value = module.team_c_vpc.gke_nodes_subnet_cidr
}

output "team_c_pod_range_name" {
  value = module.team_c_vpc.pod_range_name
}

output "team_c_services_range_name" {
  value = module.team_c_vpc.services_range_name
}

output "team_c_spoke_gateway_name" {
  value     = module.team_c_spoke.spoke_gateway.gw_name
  sensitive = true
}

#####################
# Database Spoke
#####################

output "db_vpc_name" {
  value = module.spoke_db.vpc.name
}

output "db_dns_name" {
  value = "db.${var.dns_private_zone_name}"
}

#####################
# Cloud DNS
#####################

output "dns_zone_name" {
  value = google_dns_managed_zone.private.name
}

output "dns_zone_dns_name" {
  value = var.dns_private_zone_name
}

#####################
# Cluster Names
#####################

output "name_prefix" {
  value = local.name_prefix
}

output "team_a_cluster_name" {
  value = local.teams["team-a"].name
}

output "team_b_cluster_name" {
  value = local.teams["team-b"].name
}

output "team_c_cluster_name" {
  value = local.teams["team-c"].name
}

#####################
# Master CIDRs
#####################

output "team_a_master_cidr" {
  value = var.team_a_master_cidr
}

output "team_b_master_cidr" {
  value = var.team_b_master_cidr
}

output "team_c_master_cidr" {
  value = var.team_c_master_cidr
}

#####################
# Shared Configuration
#####################

output "gcp_region" {
  value = var.gcp_region
}

output "gcp_project" {
  value = var.gcp_project
}

output "pod_cidr" {
  value = local.pod_cidr
}

output "services_cidr" {
  value = local.services_cidr
}
