#####################
# Pattern B: Namespace-as-a-Service — GCP Network Outputs
#####################

#####################
# Transit Gateway
#####################

output "transit_gateway_name" {
  description = "Aviatrix transit gateway name"
  value       = module.gcp_transit.transit_gateway.gw_name
  sensitive   = true
}

#####################
# Shared Cluster VPC
#####################

output "shared_network_name" {
  description = "Shared cluster VPC network name"
  value       = module.shared_vpc.network_name
}

output "shared_network_id" {
  description = "Shared cluster VPC network ID (self-link)"
  value       = module.shared_vpc.network_id
}

output "shared_network_self_link" {
  description = "Shared cluster VPC network self link"
  value       = module.shared_vpc.network_self_link
}

output "shared_gke_nodes_subnet_name" {
  description = "Shared GKE node subnet name"
  value       = module.shared_vpc.gke_nodes_subnet_name
}

output "shared_gke_nodes_subnet_cidr" {
  description = "Shared GKE node subnet CIDR"
  value       = module.shared_vpc.gke_nodes_subnet_cidr
}

output "shared_pod_range_name" {
  description = "Shared pod secondary range name"
  value       = module.shared_vpc.pod_range_name
}

output "shared_services_range_name" {
  description = "Shared services secondary range name"
  value       = module.shared_vpc.services_range_name
}

#####################
# Spoke Gateway
#####################

output "shared_spoke_gateway_name" {
  description = "Shared spoke gateway name"
  value       = module.shared_spoke.spoke_gateway.gw_name
  sensitive   = true
}

output "shared_spoke_gateway_private_ip" {
  description = "Shared spoke gateway private IP (used for SNAT)"
  value       = module.shared_spoke.spoke_gateway.private_ip
  sensitive   = true
}

#####################
# DNS
#####################

output "dns_zone_name" {
  description = "Cloud DNS private zone name (resource name, for ExternalDNS)"
  value       = google_dns_managed_zone.private.name
}

output "dns_zone_dns_name" {
  description = "Cloud DNS private zone DNS name (domain name, for ExternalDNS)"
  value       = var.dns_private_zone_name
}

#####################
# Cluster Configuration
#####################

output "shared_cluster_name" {
  description = "Shared GKE cluster name"
  value       = local.k8s_cluster_name
}

output "gcp_region" {
  description = "GCP region"
  value       = var.gcp_region
}

output "gcp_project" {
  description = "GCP project ID"
  value       = var.gcp_project
}

output "pod_cidr" {
  description = "Secondary range for pod networking"
  value       = local.pod_cidr
}

output "services_cidr" {
  description = "Secondary range for Kubernetes services"
  value       = local.services_cidr
}

output "master_ipv4_cidr_block" {
  description = "CIDR block for GKE private cluster master endpoint"
  value       = var.master_ipv4_cidr_block
}

output "name_prefix" {
  description = "Name prefix used for all resources"
  value       = local.name_prefix
}
