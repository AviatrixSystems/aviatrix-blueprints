# -----------------------------------------------------------------------------
# Pattern C: GKE Non-Production Cluster - Outputs
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "GKE non-production cluster name"
  value       = google_container_cluster.nonprod.name
}

output "cluster_endpoint" {
  description = "GKE non-production cluster API endpoint"
  value       = google_container_cluster.nonprod.endpoint
}

output "cluster_ca_certificate" {
  description = "GKE non-production cluster CA certificate (base64)"
  value       = google_container_cluster.nonprod.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_id" {
  description = "Cluster self-link for Aviatrix SmartGroup k8s_cluster_id"
  value       = google_container_cluster.nonprod.self_link
}

output "cluster_self_link" {
  description = "GKE non-production cluster self-link"
  value       = google_container_cluster.nonprod.self_link
}

output "cluster_location" {
  description = "GKE non-production cluster location"
  value       = google_container_cluster.nonprod.location
}

output "node_service_account_email" {
  description = "Service account email used by the GKE node pool (consumed by nodes/nonprod)."
  value       = google_service_account.node.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool for the cluster"
  value       = "${var.gcp_project_id}.svc.id.goog"
}
