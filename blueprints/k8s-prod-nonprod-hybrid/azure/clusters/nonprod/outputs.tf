# -----------------------------------------------------------------------------
# Pattern C: AKS Non-Production Cluster — Outputs
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "AKS non-production cluster name"
  value       = module.aks_nonprod.cluster_name
}

output "cluster_id" {
  description = "AKS non-production cluster resource ID"
  value       = module.aks_nonprod.cluster_id
}

output "cluster_fqdn" {
  description = "AKS non-production cluster FQDN"
  value       = module.aks_nonprod.cluster_fqdn
}

output "kube_config" {
  description = "AKS non-production cluster kubeconfig"
  value       = module.aks_nonprod.kube_config
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity"
  value       = module.aks_nonprod.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Kubelet managed identity object ID"
  value       = module.aks_nonprod.kubelet_identity_object_id
}

output "node_resource_group" {
  description = "Auto-generated node resource group name"
  value       = module.aks_nonprod.node_resource_group
}
