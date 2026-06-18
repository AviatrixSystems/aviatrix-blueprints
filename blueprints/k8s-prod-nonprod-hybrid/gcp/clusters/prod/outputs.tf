# -----------------------------------------------------------------------------
# Pattern C: GKE Production Cluster — Outputs
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "GKE production cluster name"
  value       = module.gke_prod.cluster_name
}

output "cluster_endpoint" {
  description = "GKE production cluster API endpoint"
  value       = module.gke_prod.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "GKE production cluster CA certificate (base64)"
  value       = module.gke_prod.cluster_ca_certificate
}

output "cluster_id" {
  description = "Cluster ID for Aviatrix SmartGroup k8s_cluster_id"
  value       = module.gke_prod.cluster_id
}

output "cluster_self_link" {
  description = "GKE production cluster self-link"
  value       = module.gke_prod.cluster_self_link
}

output "workload_identity_pool" {
  description = "Workload Identity pool for the cluster"
  value       = "${var.gcp_project_id}.svc.id.goog"
}
