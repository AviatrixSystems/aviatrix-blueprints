#####################
# Cluster Identity
#####################

output "cluster_id" {
  description = "AKS cluster ID"
  value       = module.shared_aks.cluster_id
}

output "cluster_name" {
  description = "AKS cluster name"
  value       = module.shared_aks.cluster_name
}

output "cluster_version" {
  description = "Kubernetes version"
  value       = module.shared_aks.cluster_version
}

#####################
# Cluster Endpoints
#####################

output "cluster_endpoint" {
  description = "AKS cluster private FQDN"
  value       = module.shared_aks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.shared_aks.cluster_certificate_authority_data
  sensitive   = true
}

output "kube_config_raw" {
  description = "Raw kubeconfig for the cluster"
  value       = module.shared_aks.kube_config_raw
  sensitive   = true
}

#####################
# Network
#####################

output "cluster_service_cidr" {
  description = "Kubernetes service CIDR"
  value       = module.shared_aks.cluster_service_cidr
}

output "node_resource_group" {
  description = "Auto-generated resource group for AKS node infrastructure"
  value       = module.shared_aks.node_resource_group
}

#####################
# Workload Identity
#####################

output "oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity"
  value       = module.shared_aks.oidc_issuer_url
}

output "external_dns_identity_client_id" {
  description = "Client ID of the ExternalDNS managed identity"
  value       = module.shared_aks.external_dns_identity_client_id
}

output "ingress_identity_client_id" {
  description = "Client ID of the ingress controller managed identity"
  value       = module.shared_aks.ingress_identity_client_id
}

#####################
# Configuration Helpers
#####################

output "kubectl_config_command" {
  description = "az CLI command to configure kubectl"
  value       = module.shared_aks.kubectl_config_command
}

output "external_dns_helm_values" {
  description = "Helm values for ExternalDNS with Azure Private DNS provider"
  value       = module.shared_aks.external_dns_helm_values
}
