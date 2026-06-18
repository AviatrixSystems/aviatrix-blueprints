output "node_group_id" {
  description = "EKS node group ID"
  value       = module.default_node_group.node_group_id
}

output "node_group_arn" {
  description = "EKS node group ARN"
  value       = module.default_node_group.node_group_arn
}

output "node_group_status" {
  description = "Status of the EKS node group"
  value       = module.default_node_group.node_group_status
}

output "node_group_autoscaling_group_names" {
  description = "List of the autoscaling group names"
  value       = module.default_node_group.node_group_autoscaling_group_names
}

output "iam_role_arn" {
  description = "IAM role ARN for the node group"
  value       = module.default_node_group.iam_role_arn
}
