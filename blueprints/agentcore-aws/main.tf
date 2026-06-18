# =============================================================================
# Blueprint: agentcore-aws
# Description: Validated Containment Architecture for AWS Bedrock AgentCore.
#              Projects AgentCore Runtime egress into a customer VPC (VPC mode)
#              and fronts the AgentCore API with an in-path PrivateLink consumer
#              endpoint. Aviatrix spoke gateway enforces default-deny,
#              domain-scoped egress and logged ingress via DCF.
# =============================================================================

# -----------------------------------------------------------------------------
# Aviatrix Provider
# -----------------------------------------------------------------------------
provider "aviatrix" {
  controller_ip           = var.controller_ip
  username                = var.controller_username
  password                = var.controller_password
  skip_version_validation = true
}

# -----------------------------------------------------------------------------
# AWS Providers (primary + awscc for CloudFormation-registered resources like
# AWS::BedrockAgentCore::Runtime which are not yet in hashicorp/aws)
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Blueprint   = var.name_prefix
      Environment = "lab"
      ManagedBy   = "terraform"
    }
  }
}

provider "awscc" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Amazon Linux 2023 ARM64 for the client invoker EC2
data "aws_ami" "al2023_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------
locals {
  name_prefix = var.name_prefix
  account_id  = data.aws_caller_identity.current.account_id
  azs         = slice(data.aws_availability_zones.available.names, 0, 2)

  # AgentCore runtime names must match [a-zA-Z][a-zA-Z0-9_]{0,47} (no hyphens)
  runtime_name = replace("${var.name_prefix}_hello", "-", "_")

  # Regional hostnames we want routed through the PrivateLink endpoints
  agentcore_data_host    = "bedrock-agentcore.${var.aws_region}.amazonaws.com"
  agentcore_control_host = "bedrock-agentcore-control.${var.aws_region}.amazonaws.com"

  # Aviatrix CoPilot deeplink for the UI status strip. CoPilot is co-resident
  # with the controller in most lab/Cloud Fabric deploys, so we fall back to
  # controller_ip when copilot_ip is unset. The fragment lands on the
  # Distributed Cloud Firewall policies screen (CoPilot 9.0+).
  copilot_host    = coalesce(var.copilot_ip, var.controller_ip)
  copilot_dcf_url = "https://${local.copilot_host}/security/distributed-cloud-firewall/policy"

  # ECR registry hostname is account- and region-specific. Append it to the
  # operator-supplied control-domain list so customers never have to hardcode
  # their own account ID in the variable default.
  ecr_registry_host   = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  aws_control_domains = concat(var.aws_control_domains, [local.ecr_registry_host])

  common_tags = {
    Blueprint = var.name_prefix
  }
}
