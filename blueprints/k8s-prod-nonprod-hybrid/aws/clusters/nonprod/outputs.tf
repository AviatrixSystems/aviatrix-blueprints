# -----------------------------------------------------------------------------
# Pattern C: EKS Non-Production Cluster — Outputs
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "EKS non-production cluster name"
  value       = module.eks_nonprod.cluster_name
}

output "cluster_endpoint" {
  description = "EKS non-production cluster API endpoint"
  value       = module.eks_nonprod.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS non-production cluster CA certificate (base64)"
  value       = module.eks_nonprod.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA"
  value       = module.eks_nonprod.cluster_oidc_issuer_url
}

output "cluster_oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.eks_nonprod.oidc_provider_arn
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA (consistent with other patterns)"
  value       = module.eks_nonprod.oidc_provider_arn
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks_nonprod.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.eks_nonprod.node_security_group_id
}

output "cluster_id" {
  description = "Cluster ID for Aviatrix SmartGroup k8s_cluster_id"
  value       = module.eks_nonprod.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN (used for Aviatrix kubernetes_cluster onboarding)"
  value       = module.eks_nonprod.cluster_arn
}
