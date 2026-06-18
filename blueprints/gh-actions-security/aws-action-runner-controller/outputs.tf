output "deployment_id" {
  description = "6-digit suffix appended to every named resource."
  value       = random_integer.deployment_id.result
}

output "vpc_id" {
  description = "Spoke VPC ID."
  value       = aws_vpc.this.id
}

output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "spoke_gateway_name" {
  description = "Aviatrix spoke gateway name."
  value       = aviatrix_spoke_gateway.this.gw_name
  sensitive   = true
}

output "spoke_gateway_public_ip" {
  description = "Public IP of the spoke gateway — SNAT egress IP for EKS pods."
  value       = aviatrix_spoke_gateway.this.public_ip
  sensitive   = true
}

output "arc_runner_label" {
  description = "runs-on label to use in GitHub Actions workflows to target this ARC scale set."
  value       = var.arc_runner_name
}

output "runner_smart_group_uuid" {
  description = "UUID of the DCF SmartGroup matching runner pods."
  value       = aviatrix_smart_group.runner_pods.uuid
}
