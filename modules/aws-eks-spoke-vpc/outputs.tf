#####################
# VPC
#####################

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Primary VPC CIDR."
  value       = aws_vpc.this.cidr_block
}

output "pod_cidr" {
  description = "Secondary VPC CIDR used for pod networking."
  value       = var.pod_cidr
}

output "secondary_cidr" {
  description = "Secondary VPC CIDR used for pod networking (alias of pod_cidr)."
  value       = var.pod_cidr
}

output "availability_zones" {
  description = "Availability zones used by this spoke."
  value       = local.az_names
}

#####################
# Subnets
#####################

output "avx_gateway_subnet_ids" {
  description = "Aviatrix gateway subnet IDs (one per AZ)."
  value       = aws_subnet.avx_public[*].id
}

output "avx_gateway_subnet_cidrs" {
  description = "Aviatrix gateway subnet CIDR blocks (one per AZ)."
  value       = aws_subnet.avx_public[*].cidr_block
}

output "lb_public_subnet_ids" {
  description = "Load-balancer public subnet IDs (one per AZ)."
  value       = aws_subnet.lb_public[*].id
}

output "lb_public_subnet_cidrs" {
  description = "Load-balancer public subnet CIDR blocks."
  value       = aws_subnet.lb_public[*].cidr_block
}

output "infra_private_subnet_ids" {
  description = "Infrastructure private subnet IDs -- where EKS nodes live."
  value       = aws_subnet.infra_private[*].id
}

output "infra_private_subnet_cidrs" {
  description = "Infrastructure private subnet CIDR blocks."
  value       = aws_subnet.infra_private[*].cidr_block
}

output "pod_private_subnet_ids" {
  description = "Pod private subnet IDs (from secondary CIDR) -- consumed by ENIConfig in the nodes layer."
  value       = aws_subnet.pod_private[*].id
}

output "pod_private_subnet_cidrs" {
  description = "Pod private subnet CIDR blocks."
  value       = aws_subnet.pod_private[*].cidr_block
}

output "infra_private_route_table_id" {
  description = "Infrastructure private route table ID. Aviatrix (aviatrix mode) or this module (native mode) programs routes here."
  value       = aws_route_table.infra_private.id
}

output "pod_private_route_table_id" {
  description = "Pod private route table ID."
  value       = aws_route_table.pod_private.id
}

#####################
# Spoke gateway
#####################

output "spoke_gateway_name" {
  description = "Aviatrix spoke gateway name."
  value       = module.spoke.spoke_gateway.gw_name
}

output "spoke_gateway_private_ip" {
  description = "Aviatrix spoke gateway private IP -- used as the SNAT target for pod traffic."
  value       = module.spoke.spoke_gateway.private_ip
}

output "spoke_gateway" {
  description = "Full spoke gateway object from the mc-spoke module -- exposed for advanced callers."
  value       = module.spoke.spoke_gateway
}

output "spoke_vpc" {
  description = "Spoke VPC object from the mc-spoke module."
  value       = module.spoke.vpc
}
