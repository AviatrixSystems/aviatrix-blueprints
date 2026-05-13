# =============================================================================
# Input Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Aviatrix Control Plane
# -----------------------------------------------------------------------------

variable "controller_ip" {
  description = "IP address or hostname of the Aviatrix Controller"
  type        = string
}

variable "controller_username" {
  description = "Admin username for the Aviatrix Controller"
  type        = string
  default     = "admin"
}

variable "controller_password" {
  description = "Admin password for the Aviatrix Controller"
  type        = string
  sensitive   = true
}

variable "aviatrix_aws_account_name" {
  description = "Aviatrix access account name for AWS (already onboarded in the controller)"
  type        = string
}

# -----------------------------------------------------------------------------
# AWS Configuration
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for deployment. Must be a region with AgentCore PrivateLink coverage (data plane + control plane)."
  type        = string
  default     = "us-east-2"

  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-2",
      "ap-south-1", "ap-southeast-1", "ap-southeast-2", "ap-northeast-1",
      "eu-central-1", "eu-west-1",
    ], var.aws_region)
    error_message = "Region must be one of the AgentCore-supported regions."
  }
}

# -----------------------------------------------------------------------------
# Blueprint Configuration
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "agentcore-vca"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "Name prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------

variable "transit_cidr" {
  description = "CIDR block for the Aviatrix Transit VPC"
  type        = string
  default     = "10.40.0.0/23"
}

variable "agentcore_spoke_cidr" {
  description = "CIDR block for the AgentCore spoke VPC"
  type        = string
  default     = "10.50.0.0/16"
}

variable "client_spoke_cidr" {
  description = "CIDR block for the client spoke VPC (hosts the invoker EC2)"
  type        = string
  default     = "10.60.0.0/16"
}

variable "gateway_size" {
  description = "Instance size for Aviatrix gateways"
  type        = string
  default     = "t3.medium"
}

# -----------------------------------------------------------------------------
# DCF Policy Seeds
# -----------------------------------------------------------------------------

variable "allowed_model_domains" {
  description = "Destination FQDNs for sanctioned model providers. Matched via SNI on egress from the AgentCore runtime subnet."
  type        = list(string)
  default = [
    "bedrock-runtime.us-east-2.amazonaws.com",
    "bedrock.us-east-2.amazonaws.com",
  ]
}

variable "allowed_tool_domains" {
  description = "Destination FQDNs for sanctioned tool calls. Matched via SNI on egress from the AgentCore runtime subnet."
  type        = list(string)
  default = [
    # GitHub public API + raw content hosts - used by the sample tool-using
    # agent and the URL-path scenario. URL-path IoC deny at rule 29 fires
    # BEFORE this allow, so malicious paths (shai-hulud etc.) are blocked
    # even though the parent domain is sanctioned.
    "api.github.com",
    "raw.githubusercontent.com",
    "github.com",
  ]
}

variable "allowed_mcp_server_domains" {
  description = "Destination FQDNs for sanctioned remote MCP servers. Matched via SNI. The sample MCP-mode agent connects to streamable-http MCP servers in this list; anything else is denied by default-deny."
  type        = list(string)
  default = [
    # DeepWiki public MCP server (no auth, read-only docs lookups).
    "mcp.deepwiki.com",
  ]
}

variable "aws_control_domains" {
  description = "AWS service control-plane FQDNs the agent runtime may call (STS, SSM, Secrets Manager, CloudWatch Logs, X-Ray) plus ECR hostnames required by AgentCore Runtime in VPC mode to pull the container image from the per-session microVM ENI."
  type        = list(string)
  default = [
    # Observability + identity
    "sts.us-east-2.amazonaws.com",
    "logs.us-east-2.amazonaws.com",
    "monitoring.us-east-2.amazonaws.com",
    "xray.us-east-2.amazonaws.com",
    "secretsmanager.us-east-2.amazonaws.com",
    # ECR (auth API + registry) - required for AgentCore VPC-mode image pull
    "api.ecr.us-east-2.amazonaws.com",
    "538591868388.dkr.ecr.us-east-2.amazonaws.com",
    # S3 layer bucket backing ECR image layers in us-east-2
    "prod-us-east-2-starport-layer-bucket.s3.us-east-2.amazonaws.com",
  ]
}

# -----------------------------------------------------------------------------
# Sample Agent
# -----------------------------------------------------------------------------

variable "build_agent_image" {
  description = "If true, build and push the sample agent container image via podman. If false, assume the image is already present in ECR at the tag below."
  type        = bool
  default     = true
}

variable "agent_image_tag" {
  description = "Tag for the sample agent container image."
  type        = string
  default     = "v5"
}

# -----------------------------------------------------------------------------
# UI ingress
# -----------------------------------------------------------------------------

variable "ui_ingress_cidrs" {
  description = "List of CIDR blocks allowed to reach the Streamlit UI via the ALB. Default is the operator who bootstrapped the lab. Keep this tight - the ALB publishes a public DNS name, and the SG rule is the only ingress control."
  type        = list(string)
  default     = ["45.26.1.144/32"]

  validation {
    condition = alltrue([
      for c in var.ui_ingress_cidrs : can(cidrhost(c, 0))
    ])
    error_message = "Each entry in ui_ingress_cidrs must be a valid CIDR block (e.g., 203.0.113.10/32)."
  }
}
