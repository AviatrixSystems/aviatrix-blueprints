#####################
# Pattern B: Namespace-as-a-Service — AWS Network Outputs
#####################

#####################
# Transit Gateway
#####################

output "transit_gateway_name" {
  description = "Aviatrix transit gateway name"
  value       = module.aws_transit.transit_gateway.gw_name
  sensitive   = true
}

#####################
# Shared Cluster VPC
#####################

output "shared_vpc_id" {
  description = "Shared cluster VPC ID"
  value       = module.shared_vpc.vpc_id
}

output "shared_vpc_cidr" {
  description = "Shared cluster VPC primary CIDR"
  value       = var.shared_vpc_cidr
}

output "shared_private_subnets" {
  description = "Shared VPC private subnet IDs (for EKS nodes)"
  value       = module.shared_vpc.private_subnets
}

output "shared_public_subnets" {
  description = "Shared VPC public subnet IDs"
  value       = module.shared_vpc.public_subnets
}

output "shared_pod_subnet_ids" {
  description = "Pod subnet IDs in the secondary CIDR"
  value       = aws_subnet.pods[*].id
}

output "shared_pod_subnet_azs" {
  description = "Pod subnet availability zones"
  value       = aws_subnet.pods[*].availability_zone
}

#####################
# Spoke Gateway
#####################

output "shared_spoke_gateway_name" {
  description = "Shared spoke gateway name"
  value       = module.shared_spoke.spoke_gateway.gw_name
  sensitive   = true
}

output "shared_spoke_gateway_private_ip" {
  description = "Shared spoke gateway private IP (used for SNAT)"
  value       = module.shared_spoke.spoke_gateway.private_ip
  sensitive   = true
}

#####################
# DNS
#####################

output "private_dns_zone_id" {
  description = "Route53 private hosted zone ID"
  value       = aws_route53_zone.private.zone_id
}

output "private_dns_zone_name" {
  description = "Route53 private hosted zone domain name"
  value       = var.private_dns_zone_name
}

#####################
# Cluster Configuration
#####################

output "shared_cluster_name" {
  description = "Shared EKS cluster name"
  value       = local.k8s_cluster_name
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "pod_cidr" {
  description = "Overlay CIDR for pod networking"
  value       = local.pod_cidr
}

output "name_prefix" {
  description = "Name prefix used for all resources"
  value       = local.name_prefix
}
