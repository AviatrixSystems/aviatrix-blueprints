# -----------------------------------------------------------------------------
# Pattern C: GKE Production Cluster - Outputs
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "GKE production cluster name"
  value       = google_container_cluster.prod.name
}

output "cluster_endpoint" {
  description = "GKE production cluster API endpoint"
  value       = google_container_cluster.prod.endpoint
}

output "cluster_ca_certificate" {
  description = "GKE production cluster CA certificate (base64)"
  value       = google_container_cluster.prod.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_id" {
  description = "Cluster self-link for Aviatrix SmartGroup k8s_cluster_id"
  value       = google_container_cluster.prod.self_link
}

output "cluster_self_link" {
  description = "GKE production cluster self-link"
  value       = google_container_cluster.prod.self_link
}

output "cluster_location" {
  description = "GKE production cluster location"
  value       = google_container_cluster.prod.location
}

output "node_service_account_email" {
  description = "Service account email used by the GKE node pool (consumed by nodes/prod)."
  value       = google_service_account.node.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool for the cluster"
  value       = "${var.gcp_project_id}.svc.id.goog"
}
