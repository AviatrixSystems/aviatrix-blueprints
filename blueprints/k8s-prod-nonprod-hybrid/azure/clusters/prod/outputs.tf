# -----------------------------------------------------------------------------
# Pattern C: AKS Production Cluster — Outputs
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "AKS production cluster name"
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_id" {
  description = "AKS production cluster resource ID"
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_fqdn" {
  description = "AKS production cluster FQDN"
  value       = azurerm_kubernetes_cluster.this.fqdn
}

output "kube_config" {
  description = "AKS production cluster kubeconfig"
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity"
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Kubelet managed identity object ID"
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "node_resource_group" {
  description = "Auto-generated node resource group name"
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}
