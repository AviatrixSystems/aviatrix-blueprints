output "vpc_name" {
  description = "GCP VPC name (matches Aviatrix controller's discovered VPC inventory name)"
  value       = google_compute_network.this.name
}

output "vpc_id" {
  description = "GCP VPC self_link (RFC1035 resource id)"
  value       = google_compute_network.this.id
}

output "vpc_self_link" {
  description = "GCP VPC self_link"
  value       = google_compute_network.this.self_link
}

# Aviatrix expects vpc_id in the form "<vpc_name>~-~<project_id>" for GCP.
output "aviatrix_vpc_id" {
  description = "Composite VPC id consumed by aviatrix_spoke_gateway / mc-spoke for GCP"
  value       = "${google_compute_network.this.name}~-~${var.project_id}"
}

output "nodes_subnet_id" {
  description = "GKE node subnet self_link"
  value       = google_compute_subnetwork.nodes.id
}

output "nodes_subnet_name" {
  description = "GKE node subnet name (used by google_container_cluster.subnetwork)"
  value       = google_compute_subnetwork.nodes.name
}

output "pods_range_name" {
  description = "Secondary range name for pods (used by ip_allocation_policy)"
  value       = "pods"
}

output "services_range_name" {
  description = "Secondary range name for services (used by ip_allocation_policy)"
  value       = "services"
}

output "avx_gw_subnet_cidr" {
  description = "Aviatrix spoke gateway subnet CIDR (consumed by mc-spoke gw_subnet)"
  value       = google_compute_subnetwork.avx_gw.ip_cidr_range
}

output "proxy_only_subnet_id" {
  description = "Regional proxy-only subnet id (null if not created)"
  value       = try(google_compute_subnetwork.proxy_only[0].id, null)
}
