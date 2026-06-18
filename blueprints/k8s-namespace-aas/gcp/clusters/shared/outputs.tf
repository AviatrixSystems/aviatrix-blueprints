#####################
# Pattern B: Namespace-as-a-Service — GCP Shared GKE Cluster Outputs
#
# This outputs.tf was explicitly created for the NaaS pattern.
# (Was missing in prior GKE code — each cluster layer MUST export
# endpoint, CA cert, name, and location for downstream layers.)
#####################

output "cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = module.shared_gke.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64 encoded cluster CA certificate"
  value       = module.shared_gke.cluster_ca_certificate
  sensitive   = true
}

output "cluster_name" {
  description = "GKE cluster name"
  value       = module.shared_gke.cluster_name
}

output "cluster_location" {
  description = "GKE cluster location (region)"
  value       = module.shared_gke.cluster_location
}

output "external_dns_service_account_email" {
  description = "Service account email for ExternalDNS Workload Identity Federation"
  value       = module.shared_gke.external_dns_service_account_email
}

output "cluster_id" {
  description = "GKE cluster ID for Aviatrix onboarding"
  value       = module.shared_gke.cluster_id
}
