#####################
# Identifiers consumed by clusters/* and nodes/*
#####################

output "name_prefix" {
  description = "Blueprint name prefix (e.g., 'gke-demo'); reused by downstream layers when naming resources."
  value       = var.name_prefix
}

output "gcp_project_id" {
  description = "GCP project ID owning the VPCs, GKE clusters, and DB VM."
  value       = var.gcp_project_id
}

output "gcp_region" {
  description = "GCP region for subnets and zonal resources (e.g., 'us-central1')."
  value       = var.gcp_region
}

output "gcp_zone" {
  description = "GCP zone for zonal GKE clusters and the DB VM (e.g., 'us-central1-a')."
  value       = var.gcp_zone
}

output "private_dns_zone_name" {
  description = "Cloud DNS private zone name (with trailing dot — Cloud DNS native form)"
  value       = var.private_dns_zone_name
}

output "private_dns_zone_resource_name" {
  description = "Cloud DNS managed-zone resource name (used by ExternalDNS Workload Identity policy bindings)"
  value       = google_dns_managed_zone.main.name
}

#####################
# Frontend
#####################

output "frontend_cluster_name" {
  description = "Name of the frontend GKE cluster (e.g., '<name_prefix>-frontend')."
  value       = local.clusters.frontend.name
}

output "frontend_cluster_id" {
  description = "Constructed GKE cluster self_link for K8s SmartGroups (matches what clusters/frontend onboards)"
  value       = local.frontend_cluster_id
}

output "frontend_vpc_name" {
  description = "Name of the frontend GKE spoke VPC."
  value       = module.frontend_vpc.vpc_name
}

output "frontend_vpc_self_link" {
  description = "Frontend VPC self_link, consumed by clusters/frontend when creating the GKE cluster."
  value       = module.frontend_vpc.vpc_self_link
}

output "frontend_nodes_subnet_name" {
  description = "Frontend node subnet name (primary range hosts GKE node IPs)."
  value       = module.frontend_vpc.nodes_subnet_name
}

output "frontend_pods_range_name" {
  description = "Secondary range alias for frontend pod IPs."
  value       = module.frontend_vpc.pods_range_name
}

output "frontend_services_range_name" {
  description = "Secondary range alias for frontend ClusterIP services."
  value       = module.frontend_vpc.services_range_name
}

output "frontend_master_cidr" {
  description = "GKE control-plane CIDR (/28) for the frontend cluster."
  value       = var.frontend_master_cidr
}

output "frontend_spoke_gateway_public_ip" {
  description = "Public egress IP of the frontend spoke GW (must be allowlisted on the GKE master_authorized_networks)"
  value       = nonsensitive(module.frontend_spoke.spoke_gateway.public_ip)
}

output "frontend_gateway_global_ip_name" {
  description = "Reserved global address name for the GKE Gateway (referenced by HTTPRoute / Gateway annotations in nodes/frontend)"
  value       = google_compute_global_address.frontend_gateway.name
}

output "frontend_gateway_global_ip_address" {
  description = "Reserved IPv4 address for the frontend Gateway"
  value       = google_compute_global_address.frontend_gateway.address
}

#####################
# Backend
#####################

output "backend_cluster_name" {
  description = "Name of the backend GKE cluster (e.g., '<name_prefix>-backend')."
  value       = local.clusters.backend.name
}

output "backend_cluster_id" {
  description = "Constructed GKE cluster self_link for K8s SmartGroups (matches what clusters/backend onboards)"
  value       = local.backend_cluster_id
}

output "backend_vpc_name" {
  description = "Name of the backend GKE spoke VPC."
  value       = module.backend_vpc.vpc_name
}

output "backend_vpc_self_link" {
  description = "Backend VPC self_link, consumed by clusters/backend when creating the GKE cluster."
  value       = module.backend_vpc.vpc_self_link
}

output "backend_nodes_subnet_name" {
  description = "Backend node subnet name (primary range hosts GKE node IPs)."
  value       = module.backend_vpc.nodes_subnet_name
}

output "backend_pods_range_name" {
  description = "Secondary range alias for backend pod IPs."
  value       = module.backend_vpc.pods_range_name
}

output "backend_services_range_name" {
  description = "Secondary range alias for backend ClusterIP services."
  value       = module.backend_vpc.services_range_name
}

output "backend_master_cidr" {
  description = "GKE control-plane CIDR (/28) for the backend cluster."
  value       = var.backend_master_cidr
}

output "backend_spoke_gateway_public_ip" {
  description = "Public egress IP of the backend spoke GW (must be allowlisted on the GKE master_authorized_networks)."
  value       = nonsensitive(module.backend_spoke.spoke_gateway.public_ip)
}

output "backend_gateway_global_ip_name" {
  description = "Reserved global address name for the GKE Gateway (referenced by HTTPRoute / Gateway annotations in nodes/backend)."
  value       = google_compute_global_address.backend_gateway.name
}

output "backend_gateway_global_ip_address" {
  description = "Reserved IPv4 address for the backend Gateway."
  value       = google_compute_global_address.backend_gateway.address
}

#####################
# Pod / service ranges (shared)
#####################

output "frontend_pods_cidr" {
  description = "CIDR of the frontend pod alias range (echoes var.frontend_pods_cidr)."
  value       = var.frontend_pods_cidr
}

output "backend_pods_cidr" {
  description = "CIDR of the backend pod alias range (echoes var.backend_pods_cidr)."
  value       = var.backend_pods_cidr
}

output "services_cidr" {
  description = "CIDR of the GKE services secondary range (shared across both clusters; never leaves the cluster)."
  value       = var.services_cidr
}

#####################
# DCF outputs (validation / cross-references)
#####################

output "dcf_ruleset_uuid" {
  description = "UUID of the gke-demo DCF ruleset created by this layer."
  value       = aviatrix_dcf_ruleset.gke_demo.id
}

output "smartgroup_frontend_vpc_uuid" {
  description = "UUID of the SmartGroup matching the frontend VPC CIDR."
  value       = aviatrix_smart_group.frontend_vpc.uuid
}

output "smartgroup_backend_vpc_uuid" {
  description = "UUID of the SmartGroup matching the backend VPC CIDR."
  value       = aviatrix_smart_group.backend_vpc.uuid
}

output "webgroup_gcp_required_uuid" {
  description = "UUID of the WebGroup matching GCP-required egress endpoints (storage, container registry, etc.)."
  value       = aviatrix_web_group.gcp_required.uuid
}

output "webgroup_github_aviatrix_uuid" {
  description = "UUID of the WebGroup matching the AviatrixSystems GitHub org (used by Helm chart fetches)."
  value       = aviatrix_web_group.github_aviatrix.uuid
}

output "smartgroup_frontend_gatus_ns_uuid" {
  description = "UUID of the K8s-typed SmartGroup matching the gatus namespace on the frontend cluster (null when enable_k8s_smartgroup_demo = false)."
  value       = try(aviatrix_smart_group.frontend_gatus_ns[0].uuid, null)
}

output "smartgroup_backend_gatus_ns_uuid" {
  description = "UUID of the K8s-typed SmartGroup matching the gatus namespace on the backend cluster (null when enable_k8s_smartgroup_demo = false)."
  value       = try(aviatrix_smart_group.backend_gatus_ns[0].uuid, null)
}
