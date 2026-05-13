#####################
# Pattern B: Namespace-as-a-Service - GCP Shared GKE Cluster Outputs
#####################

output "cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64 encoded cluster CA certificate"
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "GKE cluster location (region)"
  value       = google_container_cluster.this.location
}

output "external_dns_service_account_email" {
  description = "Service account email for ExternalDNS Workload Identity Federation"
  value       = google_service_account.external_dns.email
}

output "cluster_id" {
  description = "GKE cluster self-link — consumed by aviatrix_kubernetes_cluster and DCF SmartGroups"
  value       = google_container_cluster.this.self_link
}
