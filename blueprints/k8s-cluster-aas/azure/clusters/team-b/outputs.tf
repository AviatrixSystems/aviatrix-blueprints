output "cluster_name" {
  description = "AKS cluster name"
  value       = module.team_b_aks.cluster_name
}

output "cluster_endpoint" {
  description = "AKS cluster API server endpoint"
  value       = module.team_b_aks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded CA certificate for the AKS cluster"
  value       = module.team_b_aks.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity federation"
  value       = module.team_b_aks.oidc_issuer_url
}

output "external_dns_identity_client_id" {
  description = "Client ID of the managed identity used by ExternalDNS"
  value       = module.team_b_aks.external_dns_identity_client_id
}

output "ingress_identity_client_id" {
  description = "Client ID of the managed identity used by the ingress controller"
  value       = module.team_b_aks.ingress_identity_client_id
}

output "external_dns_helm_values" {
  description = "Pre-rendered Helm values for ExternalDNS with workload identity annotations"
  value       = module.team_b_aks.external_dns_helm_values
}

output "kube_config_raw" {
  description = "Raw kubeconfig for the AKS cluster"
  value       = module.team_b_aks.kube_config_raw
  sensitive   = true
}

output "cluster_id" {
  description = "AKS cluster ID for Aviatrix onboarding"
  value       = module.team_b_aks.cluster_id
}
