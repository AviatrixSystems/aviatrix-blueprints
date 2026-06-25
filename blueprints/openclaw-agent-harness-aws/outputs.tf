output "vpc_id" {
  description = "AWS VPC ID."
  value       = aws_vpc.this.id
}

output "agent_private_subnet_ids" {
  description = "Private subnets protected by the Aviatrix Spoke Gateway path."
  value       = aws_subnet.agent_private[*].id
}

output "agent_private_route_table_id" {
  description = "Private route table intended to receive the Aviatrix gateway default route."
  value       = aws_route_table.agent_private.id
}

output "agent_private_cidrs" {
  description = "Private CIDRs used as the source SmartGroup."
  value       = local.private_subnet_cidrs
}

output "vpc_dns_resolver_ip" {
  description = "AWS VPC DNS resolver IP explicitly allowed before external DNS deny."
  value       = local.vpc_dns_resolver_ip
}

output "agent_instance_id" {
  description = "Private OpenClaw/NemoClaw VM instance ID. Use SSM Session Manager to connect."
  value       = aws_instance.agent.id
}

output "agent_private_ip" {
  description = "Private IP of the OpenClaw/NemoClaw VM."
  value       = aws_instance.agent.private_ip
}

output "vpc_flow_log_group" {
  description = "CloudWatch log group receiving VPC Flow Logs. Null when enable_vpc_flow_logs=false."
  value       = try(aws_cloudwatch_log_group.vpc_flow_logs[0].name, null)
}

output "aviatrix_spoke_gateway" {
  description = "Aviatrix Spoke Gateway object returned by the mc-spoke module."
  value       = module.spoke.spoke_gateway
  sensitive   = true
}

output "agent_source_smart_group" {
  description = "Aviatrix SmartGroup name used as the source for agent policies (tag-based / workload-aware)."
  value       = aviatrix_smart_group.agent_workload.name
}

output "policy_mode" {
  description = "Current DCF mode. monitor logs would-be denies; enforce blocks them."
  value       = var.policy_mode
}

output "ssm_start_session" {
  description = "Command to access the private agent VM."
  value       = "aws ssm start-session --target ${aws_instance.agent.id} --region ${var.aws_region}"
}

output "agent_class" {
  description = "Agent class tag for this deployment."
  value       = var.agent_class
}

output "managed_controller_policy" {
  description = "Whether this deployment owns the controller-level DCF policy list and POST_RULES default action."
  value       = var.manage_controller_policy
}

output "ssm_interface_endpoint_ids" {
  description = "Private interface endpoints used for SSM access. Empty when create_ssm_vpc_endpoints=false."
  value       = { for name, endpoint in aws_vpc_endpoint.interface : name => endpoint.id }
}

output "s3_gateway_endpoint_id" {
  description = "S3 gateway endpoint ID. Null when create_s3_gateway_endpoint=false."
  value       = try(aws_vpc_endpoint.s3[0].id, null)
}

output "next_steps" {
  description = "Operator next steps after apply."
  value = [
    "1. Start a private session: aws ssm start-session --target ${aws_instance.agent.id} --region ${var.aws_region}",
    "2. Review /opt/openclaw-vca/README.txt and run the selected installer manually.",
    "3. Run POLICY_MODE=${var.policy_mode} /opt/openclaw-vca/verify-egress.sh from the VM.",
    "4. In CoPilot FlowIQ, filter by SmartGroup ${local.name}-sg-agent-workload and convert legitimate destinations into WebGroup tfvars.",
    "5. After representative tests pass in monitor mode, switch policy_mode to enforce."
  ]
}
