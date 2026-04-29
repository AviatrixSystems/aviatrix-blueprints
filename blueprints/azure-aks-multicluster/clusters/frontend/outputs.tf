output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "cluster_id" {
  description = "AKS cluster Azure resource ID"
  value       = azurerm_kubernetes_cluster.aks.id
}

output "cluster_fqdn" {
  description = "AKS API server FQDN"
  value       = azurerm_kubernetes_cluster.aks.fqdn
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL (for Workload Identity federation)"
  value       = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "kube_config_raw" {
  description = "Raw kubeconfig for kubectl access"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

output "host" {
  description = "AKS API server URL (for Kubernetes/Helm providers)"
  value       = azurerm_kubernetes_cluster.aks.kube_config[0].host
  sensitive   = true
}

output "client_certificate" {
  description = "Client certificate for Kubernetes provider auth"
  value       = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  sensitive   = true
}

output "client_key" {
  description = "Client key for Kubernetes provider auth"
  value       = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate for Kubernetes provider auth"
  value       = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  sensitive   = true
}

output "resource_group_name" {
  description = "Resource group containing the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.resource_group_name
}

output "node_resource_group" {
  description = "Auto-generated resource group for AKS node VMs (MC_...)"
  value       = azurerm_kubernetes_cluster.aks.node_resource_group
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet managed identity (for ACR pull permissions)"
  value       = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

output "aks_identity_principal_id" {
  description = "Principal ID of the AKS cluster managed identity"
  value       = azurerm_user_assigned_identity.aks.principal_id
}

output "external_dns_client_id" {
  description = "Client ID of the ExternalDNS managed identity (for Workload Identity annotation)"
  value       = azurerm_user_assigned_identity.external_dns.client_id
}

output "kubectl_config_command" {
  description = "Command to configure kubectl for this cluster — context name matches what the README uses (`frontend`) so subsequent `kubectl ... --context frontend` commands work as documented"
  value       = "az aks get-credentials --resource-group ${azurerm_kubernetes_cluster.aks.resource_group_name} --name ${azurerm_kubernetes_cluster.aks.name} --context frontend --overwrite-existing"
}

output "aviatrix_cluster_id" {
  description = "Lowercased cluster_id used for Aviatrix onboarding (also the SmartGroup k8s_cluster_id selector value)"
  value       = lower(azurerm_kubernetes_cluster.aks.id)
}

output "aviatrix_onboarded" {
  description = "Whether this cluster is registered with the Aviatrix Controller"
  value       = var.enable_aviatrix_onboarding
}
