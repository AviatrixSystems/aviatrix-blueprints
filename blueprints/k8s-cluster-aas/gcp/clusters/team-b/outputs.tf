output "cluster_name" {
  description = "GKE cluster name"
  value       = module.team_b_gke.cluster_name
}

output "cluster_endpoint" {
  description = "GKE cluster API server endpoint (without https://)"
  value       = module.team_b_gke.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64 encoded CA certificate for the GKE cluster"
  value       = module.team_b_gke.cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "GKE cluster region or zone"
  value       = module.team_b_gke.cluster_location
}

output "external_dns_service_account_email" {
  description = "GCP service account email for ExternalDNS Workload Identity"
  value       = module.team_b_gke.external_dns_service_account_email
}

output "external_dns_helm_values" {
  description = "Pre-rendered Helm values for ExternalDNS with Workload Identity annotations"
  value       = module.team_b_gke.external_dns_helm_values
}

output "cluster_id" {
  description = "GKE cluster ID for Aviatrix onboarding"
  value       = module.team_b_gke.cluster_id
}
