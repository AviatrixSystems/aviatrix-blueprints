output "cluster_name" {
  description = "EKS cluster name"
  value       = module.team_b_eks.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.team_b_eks.cluster_arn
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.team_b_eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded CA certificate"
  value       = module.team_b_eks.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.team_b_eks.oidc_provider_arn
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for ALB Controller"
  value       = module.alb_controller_irsa.iam_role_arn
}

output "external_dns_role_arn" {
  description = "IAM role ARN for ExternalDNS"
  value       = module.external_dns_irsa.iam_role_arn
}
