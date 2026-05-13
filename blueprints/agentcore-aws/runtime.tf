# =============================================================================
# AgentCore Runtime resource.
#
# The hashicorp/aws provider does not yet expose AWS::BedrockAgentCore::Runtime.
# We use awscc, which is generated from the CloudFormation registry, to create
# the runtime in VPC mode pointed at our ECR container image.
#
# agent_runtime_name constraint: [a-zA-Z][a-zA-Z0-9_]{0,47}. Hyphens are not
# allowed, so we derive the name from var.name_prefix by substituting _.
# =============================================================================

resource "awscc_bedrockagentcore_runtime" "hello" {
  agent_runtime_name = local.runtime_name
  role_arn           = aws_iam_role.agentcore_runtime.arn

  agent_runtime_artifact = {
    container_configuration = {
      container_uri = local.agent_image_uri
    }
  }

  network_configuration = {
    network_mode = "VPC"
    network_mode_config = {
      subnets         = [aws_subnet.agentcore_runtime.id]
      security_groups = [aws_security_group.runtime.id]
    }
  }

  protocol_configuration = "HTTP"

  environment_variables = {
    AGENT_MODEL_ID    = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
    ADVERSARY_MCP_URL = local.adversary_mcp_url
  }

  tags = {
    Blueprint = var.name_prefix
    Role      = "agentcore-runtime-sample"
  }

  depends_on = [
    null_resource.agent_build_push,
    aws_iam_role_policy.agentcore_runtime_inline,
    aws_vpc_endpoint.agentcore_data,
    aws_vpc_endpoint.agentcore_control,
    aws_route53_record.agentcore_data_apex,
    aws_route53_record.agentcore_control_apex,
    module.spoke_agentcore,
    aws_lambda_function_url.adversary,
  ]
}
