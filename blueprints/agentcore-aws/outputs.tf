# =============================================================================
# Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Core identifiers
# -----------------------------------------------------------------------------

output "agentcore_spoke_vpc_id" {
  value       = aws_vpc.agentcore.id
  description = "VPC ID of the AgentCore spoke"
}

output "client_spoke_vpc_id" {
  value       = aws_vpc.client.id
  description = "VPC ID of the client spoke"
}

output "agentcore_runtime_subnet_id" {
  value       = aws_subnet.agentcore_runtime.id
  description = "Private subnet where AgentCore creates per-session ENIs"
}

output "agentcore_runtime_subnet_cidr" {
  value       = aws_subnet.agentcore_runtime.cidr_block
  description = "CIDR of the runtime subnet (source of DCF subnet SmartGroup)"
}

# -----------------------------------------------------------------------------
# AgentCore Runtime
# -----------------------------------------------------------------------------

output "agentcore_runtime_arn" {
  value       = awscc_bedrockagentcore_runtime.hello.agent_runtime_arn
  description = "ARN of the sample AgentCore Runtime. Use for InvokeAgentRuntime."
}

output "agentcore_runtime_id" {
  value       = awscc_bedrockagentcore_runtime.hello.agent_runtime_id
  description = "AgentCore Runtime ID"
}

output "agent_image_uri" {
  value       = local.agent_image_uri
  description = "ECR URI of the sample agent container image"
}

# -----------------------------------------------------------------------------
# PrivateLink
# -----------------------------------------------------------------------------

output "privatelink_data_endpoint_id" {
  value       = aws_vpc_endpoint.agentcore_data.id
  description = "Interface VPC endpoint for bedrock-agentcore (data plane)"
}

output "privatelink_control_endpoint_id" {
  value       = aws_vpc_endpoint.agentcore_control.id
  description = "Interface VPC endpoint for bedrock-agentcore-control"
}

output "agentcore_data_host" {
  value       = local.agentcore_data_host
  description = "Regional data-plane hostname (Route 53 PHZ apex)"
}

output "agentcore_control_host" {
  value       = local.agentcore_control_host
  description = "Regional control-plane hostname (Route 53 PHZ apex)"
}

# -----------------------------------------------------------------------------
# Aviatrix
# -----------------------------------------------------------------------------

output "transit_gateway_name" {
  value       = module.transit.transit_gateway.gw_name
  description = "Aviatrix transit gateway name (for CoPilot queries)"
  sensitive   = true
}

output "agentcore_spoke_gateway_name" {
  value       = module.spoke_agentcore.spoke_gateway.gw_name
  description = "Aviatrix spoke gateway name for the AgentCore spoke"
  sensitive   = true
}

output "client_spoke_gateway_name" {
  value       = module.spoke_client.spoke_gateway.gw_name
  description = "Aviatrix spoke gateway name for the client spoke"
  sensitive   = true
}

output "dcf_policy_names" {
  value       = [for p in aviatrix_distributed_firewalling_policy_list.main.policies : p.name]
  description = "Ordered DCF policy names created by this blueprint"
}

# -----------------------------------------------------------------------------
# Test harness
# -----------------------------------------------------------------------------

output "client_invoker_instance_id" {
  value       = aws_instance.client_invoker.id
  description = "EC2 instance ID of the test invoker. Connect via SSM Session Manager."
}

output "ui_alb_url" {
  value       = "http://${aws_lb.ui.dns_name}/"
  description = "Public ALB URL for the Streamlit UI. Ingress is restricted to ui_ingress_cidrs at the SG layer."
}

output "ui_ingress_cidrs" {
  value       = var.ui_ingress_cidrs
  description = "CIDR blocks currently allowlisted to reach the UI ALB. Update via -var or terraform.tfvars and re-apply."
}

output "ui_tunnel_command" {
  value = format(
    "aws ec2-instance-connect ssh --region %s --instance-id %s --connection-type eice --os-user ec2-user --local-forwarding 8501:localhost:8501",
    var.aws_region,
    aws_instance.client_invoker.id,
  )
  description = "Open an SSH-over-EICE session that port-forwards the Streamlit probe UI to http://localhost:8501. Accept the host key on first run; then browse localhost:8501. Or run ./scripts/ui-tunnel.sh which wraps this."
}

output "probe_command" {
  value = format(
    "aws ssm start-session --region %s --target %s --document-name AWS-StartInteractiveCommand --parameters 'command=[\"export AGENTCORE_RUNTIME_ARN=%s AGENTCORE_DATA_HOST=%s AWS_REGION=%s; /usr/local/bin/probe-agentcore.sh\"]'",
    var.aws_region,
    aws_instance.client_invoker.id,
    awscc_bedrockagentcore_runtime.hello.agent_runtime_arn,
    local.agentcore_data_host,
    var.aws_region,
  )
  description = "One-liner to run the probe against the sample runtime from the client invoker"
}

# -----------------------------------------------------------------------------
# Guardrails
# -----------------------------------------------------------------------------

output "vpc_mode_guardrail_policy_arn" {
  value       = aws_iam_policy.vpc_mode_guardrail.arn
  description = "ARN of the managed IAM policy that blocks AgentCore creates outside the approved spoke. Attach to human-admin roles."
}
