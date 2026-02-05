output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Primary VPC CIDR block"
  value       = aws_vpc.this.cidr_block
}

output "secondary_cidr" {
  description = "Secondary VPC CIDR block for pods"
  value       = var.secondary_cidr
}

output "avx_gateway_subnet_cidrs" {
  description = "CIDR blocks of Aviatrix gateway subnets"
  value       = aws_subnet.avx_public[*].cidr_block
}

output "avx_gateway_subnet_ids" {
  description = "IDs of Aviatrix gateway subnets"
  value       = aws_subnet.avx_public[*].id
}

output "lb_public_subnet_ids" {
  description = "IDs of load balancer public subnets"
  value       = aws_subnet.lb_public[*].id
}

output "lb_public_subnet_cidrs" {
  description = "CIDR blocks of load balancer public subnets"
  value       = aws_subnet.lb_public[*].cidr_block
}

output "infra_private_subnet_ids" {
  description = "IDs of infrastructure private subnets (for EKS nodes)"
  value       = aws_subnet.infra_private[*].id
}

output "infra_private_subnet_cidrs" {
  description = "CIDR blocks of infrastructure private subnets"
  value       = aws_subnet.infra_private[*].cidr_block
}

output "pod_private_subnet_ids" {
  description = "IDs of pod private subnets (from secondary CIDR)"
  value       = aws_subnet.pod_private[*].id
}

output "pod_private_subnet_cidrs" {
  description = "CIDR blocks of pod private subnets"
  value       = aws_subnet.pod_private[*].cidr_block
}

output "private_route_table_id" {
  description = "ID of private route table (managed by Aviatrix)"
  value       = aws_route_table.private.id
}

output "availability_zones" {
  description = "Availability zones used"
  value       = local.az_names
}
