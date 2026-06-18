# -----------------------------------------------------------------------------
# Pattern C: AKS Production Cluster — Outputs
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "AKS production cluster name"
  value       = module.aks_prod.cluster_name
}

output "cluster_id" {
  description = "AKS production cluster resource ID"
  value       = module.aks_prod.cluster_id
}

output "cluster_fqdn" {
  description = "AKS production cluster FQDN"
  value       = module.aks_prod.cluster_fqdn
}

output "kube_config" {
  description = "AKS production cluster kubeconfig"
  value       = module.aks_prod.kube_config
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity"
  value       = module.aks_prod.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Kubelet managed identity object ID"
  value       = module.aks_prod.kubelet_identity_object_id
}

output "node_resource_group" {
  description = "Auto-generated node resource group name"
  value       = module.aks_prod.node_resource_group
}
