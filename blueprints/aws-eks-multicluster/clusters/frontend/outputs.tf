# VPC output (needed for ALB Controller Helm install)
output "vpc_id" {
  description = "VPC ID where the cluster is deployed"
  value       = module.frontend_eks.vpc_id
}

# Cluster identity outputs (used by node-group deployment)
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.frontend_eks.cluster_name
}

output "cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = module.frontend_eks.cluster_version
}

output "cluster_service_cidr" {
  description = "Kubernetes service CIDR"
  value       = module.frontend_eks.cluster_service_cidr
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.frontend_eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data"
  value       = module.frontend_eks.cluster_certificate_authority_data
  sensitive   = true
}

# Security group outputs (used by node-group deployment)
output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.frontend_eks.cluster_security_group_id
}

output "cluster_primary_security_group_id" {
  description = "Primary security group ID of the cluster (for node groups)"
  value       = module.frontend_eks.cluster_primary_security_group_id
}

output "node_security_group_id" {
  description = "Security group ID for EKS nodes"
  value       = module.frontend_eks.node_security_group_id
}

output "pod_security_group_id" {
  description = "Security group ID for EKS pods"
  value       = module.frontend_eks.pod_security_group_id
}

# OIDC outputs (for IRSA)
output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL"
  value       = module.frontend_eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN"
  value       = module.frontend_eks.oidc_provider_arn
}

# IAM role outputs
output "alb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = module.frontend_eks.alb_controller_role_arn
}

output "external_dns_role_arn" {
  description = "IAM role ARN for ExternalDNS"
  value       = module.frontend_eks.external_dns_role_arn
}

# Kubectl configuration
output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = module.frontend_eks.configure_kubectl
}

# ENIConfig outputs
output "eniconfig_manifests" {
  description = "ENIConfig YAML manifests for custom networking"
  value       = module.frontend_eks.eniconfig_manifests
}

# Helm values for ExternalDNS
output "external_dns_helm_values" {
  description = "Helm values for ExternalDNS deployment"
  value       = module.frontend_eks.external_dns_helm_values
}
