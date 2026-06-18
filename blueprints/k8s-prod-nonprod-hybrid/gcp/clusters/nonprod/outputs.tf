# -----------------------------------------------------------------------------
# Pattern C: GKE Non-Production Cluster — Outputs
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "GKE non-production cluster name"
  value       = module.gke_nonprod.cluster_name
}

output "cluster_endpoint" {
  description = "GKE non-production cluster API endpoint"
  value       = module.gke_nonprod.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "GKE non-production cluster CA certificate (base64)"
  value       = module.gke_nonprod.cluster_ca_certificate
}

output "cluster_id" {
  description = "Cluster ID for Aviatrix SmartGroup k8s_cluster_id"
  value       = module.gke_nonprod.cluster_id
}

output "cluster_self_link" {
  description = "GKE non-production cluster self-link"
  value       = module.gke_nonprod.cluster_self_link
}

output "workload_identity_pool" {
  description = "Workload Identity pool for the cluster"
  value       = "${var.gcp_project_id}.svc.id.goog"
}
