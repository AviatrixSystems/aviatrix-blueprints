#####################
# Transit Gateway
#####################

output "transit_gateway_name" {
  description = "Aviatrix transit gateway name"
  value       = module.aws_transit.transit_gateway.gw_name
  sensitive   = true
}

output "transit_vpc_id" {
  description = "Transit VPC ID"
  value       = module.aws_transit.vpc.vpc_id
}

#####################
# Team-A VPC and Spoke
#####################

output "team_a_vpc_id" {
  description = "Team-A VPC ID"
  value       = module.team_a_vpc.vpc_id
}

output "team_a_vpc_cidr" {
  description = "Team-A VPC primary CIDR"
  value       = local.teams["team-a"].vpc_cidr
}

output "team_a_private_subnet_ids" {
  description = "Team-A private subnet IDs (for EKS node groups)"
  value       = module.team_a_vpc.private_subnets
}

output "team_a_public_subnet_ids" {
  description = "Team-A public subnet IDs"
  value       = module.team_a_vpc.public_subnets
}

output "team_a_pod_subnet_ids" {
  description = "Team-A pod subnet IDs (secondary CIDR for VPC CNI custom networking)"
  value       = aws_subnet.team_a_pods[*].id
}

output "team_a_spoke_gateway_name" {
  description = "Team-A spoke gateway name"
  value       = module.team_a_spoke.spoke_gateway.gw_name
  sensitive   = true
}

output "team_a_spoke_gateway_private_ip" {
  description = "Team-A spoke gateway private IP for SNAT"
  value       = module.team_a_spoke.spoke_gateway.private_ip
  sensitive   = true
}

#####################
# Team-B VPC and Spoke
#####################

output "team_b_vpc_id" {
  description = "Team-B VPC ID"
  value       = module.team_b_vpc.vpc_id
}

output "team_b_vpc_cidr" {
  description = "Team-B VPC primary CIDR"
  value       = local.teams["team-b"].vpc_cidr
}

output "team_b_private_subnet_ids" {
  description = "Team-B private subnet IDs (for EKS node groups)"
  value       = module.team_b_vpc.private_subnets
}

output "team_b_public_subnet_ids" {
  description = "Team-B public subnet IDs"
  value       = module.team_b_vpc.public_subnets
}

output "team_b_pod_subnet_ids" {
  description = "Team-B pod subnet IDs (secondary CIDR for VPC CNI custom networking)"
  value       = aws_subnet.team_b_pods[*].id
}

output "team_b_spoke_gateway_name" {
  description = "Team-B spoke gateway name"
  value       = module.team_b_spoke.spoke_gateway.gw_name
  sensitive   = true
}

output "team_b_spoke_gateway_private_ip" {
  description = "Team-B spoke gateway private IP for SNAT"
  value       = module.team_b_spoke.spoke_gateway.private_ip
  sensitive   = true
}

#####################
# Team-C VPC and Spoke
#####################

output "team_c_vpc_id" {
  description = "Team-C VPC ID"
  value       = module.team_c_vpc.vpc_id
}

output "team_c_vpc_cidr" {
  description = "Team-C VPC primary CIDR"
  value       = local.teams["team-c"].vpc_cidr
}

output "team_c_private_subnet_ids" {
  description = "Team-C private subnet IDs (for EKS node groups)"
  value       = module.team_c_vpc.private_subnets
}

output "team_c_public_subnet_ids" {
  description = "Team-C public subnet IDs"
  value       = module.team_c_vpc.public_subnets
}

output "team_c_pod_subnet_ids" {
  description = "Team-C pod subnet IDs (secondary CIDR for VPC CNI custom networking)"
  value       = aws_subnet.team_c_pods[*].id
}

output "team_c_spoke_gateway_name" {
  description = "Team-C spoke gateway name"
  value       = module.team_c_spoke.spoke_gateway.gw_name
  sensitive   = true
}

output "team_c_spoke_gateway_private_ip" {
  description = "Team-C spoke gateway private IP for SNAT"
  value       = module.team_c_spoke.spoke_gateway.private_ip
  sensitive   = true
}

#####################
# Database Spoke
#####################

output "db_vpc_id" {
  description = "Database spoke VPC ID"
  value       = module.spoke_db.vpc.vpc_id
}

output "db_private_ip" {
  description = "Database private IP address"
  value       = var.db_private_ip
}

output "db_dns_name" {
  description = "Database DNS name"
  value       = "db.${var.private_dns_zone_name}"
}

#####################
# Route53 DNS
#####################

output "route53_zone_id" {
  description = "Route53 private hosted zone ID"
  value       = aws_route53_zone.private.zone_id
}

output "private_dns_zone_name" {
  description = "Route53 private hosted zone domain name"
  value       = var.private_dns_zone_name
}

#####################
# Cluster Names
#####################

output "name_prefix" {
  description = "Name prefix used for all resources"
  value       = local.name_prefix
}

output "team_a_cluster_name" {
  description = "Team-A EKS cluster name"
  value       = "${local.name_prefix}-team-a"
}

output "team_b_cluster_name" {
  description = "Team-B EKS cluster name"
  value       = "${local.name_prefix}-team-b"
}

output "team_c_cluster_name" {
  description = "Team-C EKS cluster name"
  value       = "${local.name_prefix}-team-c"
}

#####################
# Shared Configuration
#####################

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "pod_cidr" {
  description = "Overlay CIDR for pod networking (overlapping across VPCs)"
  value       = local.pod_cidr
}
