#####################
# Cluster Identity
#####################

output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.shared_eks.cluster_id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.shared_eks.cluster_name
}

output "cluster_version" {
  description = "Kubernetes version"
  value       = module.shared_eks.cluster_version
}

#####################
# Cluster Endpoints
#####################

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.shared_eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.shared_eks.cluster_certificate_authority_data
  sensitive   = true
}

#####################
# Network
#####################

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.shared_eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.shared_eks.node_security_group_id
}

#####################
# IRSA
#####################

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.shared_eks.oidc_provider_arn
}

output "oidc_provider" {
  description = "OIDC provider URL (without https://)"
  value       = module.shared_eks.oidc_provider
}

#####################
# Configuration Helpers
#####################

output "kubectl_config_command" {
  description = "aws CLI command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${data.terraform_remote_state.network.outputs.aws_region} --name ${module.shared_eks.cluster_name}"
}

#####################
# Aviatrix
#####################

output "cluster_arn" {
  description = "EKS cluster ARN (used for Aviatrix kubernetes_cluster onboarding)"
  value       = module.shared_eks.cluster_arn
}
