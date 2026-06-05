output "vpc_id" {
  description = "Spoke VPC ID. Consumed by the cluster and nodes layers."
  value       = module.spoke_vpc.vpc_id
}

output "vpc_cidr" {
  description = "Primary VPC CIDR."
  value       = module.spoke_vpc.vpc_cidr
}

output "secondary_cidr" {
  description = "Secondary VPC CIDR used for pod networking (VPC CNI custom networking)."
  value       = module.spoke_vpc.secondary_cidr
}

output "availability_zones" {
  description = "Availability zones the spoke VPC subnets are placed in."
  value       = module.spoke_vpc.availability_zones
}

output "cluster_name" {
  description = "EKS cluster name derived from name_prefix; consumed by the cluster and nodes layers."
  value       = local.cluster_name
}

output "lb_public_subnet_ids" {
  description = "Public load-balancer subnet IDs (for the AWS Load Balancer Controller / ALB)."
  value       = module.spoke_vpc.lb_public_subnet_ids
}

output "infra_private_subnet_ids" {
  description = "Infrastructure private subnet IDs where EKS nodes and the control-plane ENIs live."
  value       = module.spoke_vpc.infra_private_subnet_ids
}

output "infra_private_subnet_cidrs" {
  description = "Infrastructure private subnet CIDR blocks."
  value       = module.spoke_vpc.infra_private_subnet_cidrs
}

output "pod_private_subnet_ids" {
  description = "Pod private subnet IDs (from the secondary CIDR); consumed by the nodes layer ENIConfig."
  value       = module.spoke_vpc.pod_private_subnet_ids
}

output "spoke_gateway_name" {
  description = "Aviatrix spoke gateway name (used for DCF SmartGroup references and post-attach automation)."
  value       = module.spoke_vpc.spoke_gateway_name
  sensitive   = true
}

output "spoke_gateway_private_ip" {
  description = "Aviatrix spoke gateway private IP (the SNAT target for pod and node egress)."
  value       = module.spoke_vpc.spoke_gateway_private_ip
  sensitive   = true
}
