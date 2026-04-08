#####################
# EKS Cluster
#####################

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster CA certificate (base64)"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

#####################
# Networking
#####################

output "vpc_id" {
  description = "Application VPC ID"
  value       = aws_vpc.this.id
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

#####################
# IRSA Roles
#####################

output "alb_controller_role_arn" {
  description = "IAM role ARN for ALB controller service account"
  value       = module.iam_irsa_alb_controller.arn
}

output "litellm_bedrock_role_arn" {
  description = "IAM role ARN for LiteLLM Bedrock access"
  value       = module.iam_irsa_litellm.arn
}

#####################
# Aviatrix
#####################

output "spoke_gateway_name" {
  description = "Aviatrix spoke gateway name"
  value       = module.spoke.spoke_gateway.gw_name
  sensitive   = true
}

output "transit_gateway_name" {
  description = "Aviatrix transit gateway name"
  value       = module.aws_transit.transit_gateway.gw_name
  sensitive   = true
}
