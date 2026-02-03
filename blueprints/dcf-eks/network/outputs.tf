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
# Frontend VPC and Spoke
#####################

output "frontend_vpc_id" {
  description = "Frontend VPC ID"
  value       = module.frontend_vpc.vpc_id
}

output "frontend_vpc_cidr" {
  description = "Frontend VPC primary CIDR"
  value       = module.frontend_vpc.vpc_cidr
}

output "frontend_infra_private_subnet_ids" {
  description = "Frontend infrastructure private subnet IDs for EKS nodes"
  value       = module.frontend_vpc.infra_private_subnet_ids
}

output "frontend_pod_private_subnet_ids" {
  description = "Frontend pod private subnet IDs"
  value       = module.frontend_vpc.pod_private_subnet_ids
}

output "frontend_availability_zones" {
  description = "Frontend availability zones"
  value       = module.frontend_vpc.availability_zones
}

output "frontend_spoke_gateway_name" {
  description = "Frontend spoke gateway name"
  value       = module.frontend_spoke.spoke_gateway.gw_name
  sensitive   = true
}

output "frontend_spoke_gateway_private_ip" {
  description = "Frontend spoke gateway private IP for SNAT"
  value       = module.frontend_spoke.spoke_gateway.private_ip
  sensitive   = true
}

#####################
# Backend VPC and Spoke
#####################

output "backend_vpc_id" {
  description = "Backend VPC ID"
  value       = module.backend_vpc.vpc_id
}

output "backend_vpc_cidr" {
  description = "Backend VPC primary CIDR"
  value       = module.backend_vpc.vpc_cidr
}

output "backend_infra_private_subnet_ids" {
  description = "Backend infrastructure private subnet IDs for EKS nodes"
  value       = module.backend_vpc.infra_private_subnet_ids
}

output "backend_pod_private_subnet_ids" {
  description = "Backend pod private subnet IDs"
  value       = module.backend_vpc.pod_private_subnet_ids
}

output "backend_availability_zones" {
  description = "Backend availability zones"
  value       = module.backend_vpc.availability_zones
}

output "backend_spoke_gateway_name" {
  description = "Backend spoke gateway name"
  value       = module.backend_spoke.spoke_gateway.gw_name
  sensitive   = true
}

output "backend_spoke_gateway_private_ip" {
  description = "Backend spoke gateway private IP for SNAT"
  value       = module.backend_spoke.spoke_gateway.private_ip
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
  description = "Apache VM private IP address"
  value       = module.db.vm_private_ip
}

output "db_dns_name" {
  description = "Database DNS name"
  value       = "db.${var.route53_private_zone_name}"
}

#####################
# Route53 DNS
#####################

output "route53_zone_id" {
  description = "Route53 private hosted zone ID (for EKS ExternalDNS)"
  value       = aws_route53_zone.private.zone_id
}

output "route53_zone_name" {
  description = "Route53 private hosted zone name (for EKS ExternalDNS)"
  value       = aws_route53_zone.private.name
}

#####################
# Shared Configuration
#####################

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "secondary_cidr" {
  description = "Secondary CIDR for pod networking (overlapping across VPCs)"
  value       = local.secondary_cidr
}

