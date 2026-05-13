# =============================================================================
# Input Variables
# =============================================================================

# -----------------------------------------------------------------------------
# AWS
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Private subnets are /24 slices; the public subnet (spoke gateway) is a /24 slice."
  type        = string
  default     = "10.10.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

# -----------------------------------------------------------------------------
# EKS
# -----------------------------------------------------------------------------

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.32"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS managed node group"
  type        = string
  default     = "m5.large"
}

variable "node_desired_size" {
  description = "Desired number of EKS nodes. Set to 0 initially; scale up after Aviatrix spoke gateway programs routes."
  type        = number
  default     = 0
}

variable "node_max_size" {
  description = "Maximum number of EKS nodes"
  type        = number
  default     = 4
}

# -----------------------------------------------------------------------------
# Aviatrix Controller (Bring Your Own — pre-existing)
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

variable "aws_access_account" {
  description = "Aviatrix access account name for AWS (onboarded in the Controller)"
  type        = string
}

variable "copilot_private_ip" {
  description = "CoPilot private IP — used for syslog stream configuration"
  type        = string
}

variable "copilot_public_ip" {
  description = "CoPilot public IP — required for spoke gateway OTEL exporters (TCP 31284) when the spoke VPC is not peered to the controlplane VNet. Without this, DCF Monitor logs stay empty even though FlowIQ works."
  type        = string
}

# -----------------------------------------------------------------------------
# Obot
# -----------------------------------------------------------------------------

variable "obot_version" {
  description = "Obot Helm chart version to deploy. Must be >= 0.21.0 for MCPNetworkPolicy support."
  type        = string
  default     = "0.21.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+", var.obot_version))
    error_message = "obot_version must be a valid semver string (e.g. 0.21.0)."
  }
}

variable "obot_admin_password" {
  description = "Obot admin password"
  type        = string
  sensitive   = true
}

variable "npc_chart_version" {
  description = "Version of the aviatrix-network-policy-controller Helm chart from charts.obot.ai. Update when Aviatrix releases a new NPC chart version."
  type        = string
  default     = "v0.0.1"
}

variable "obot_namespace" {
  description = "Kubernetes namespace for Obot"
  type        = string
  default     = "obot-system"
}

variable "obot_mcp_namespace" {
  description = "Kubernetes namespace where Obot deploys MCP server pods"
  type        = string
  default     = "obot-mcp"
}

# -----------------------------------------------------------------------------
# DCF — EKS known limitation workaround
# K8s label-based SmartGroups do not resolve on EKS (controller registers
# EKS as Partial: assetd watcher subscriptions lost on restart). These CIDR
# variables provide a V1 DENY workaround. Update after each pod restart using
# the procedure in the README.
# -----------------------------------------------------------------------------

variable "obot_system_pod_cidrs" {
  description = <<-EOT
    List of /32 CIDRs for obot-system pods. Used to scope Obot egress permits
    (Anthropic, GitHub, charts.obot.ai) to the orchestration layer only.
    TWO-STEP DEPLOY: Leave empty ([]) on first apply. After Obot is running,
    get pod IPs with:
      kubectl get pods -n obot-system -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}'
    Then re-apply with those IPs as /32 CIDRs.
  EOT
  type        = list(string)
  default     = []
}

variable "obot_mcp_pod_cidrs" {
  description = <<-EOT
    List of /32 CIDRs for active obot-mcp pods that require DCF deny-all
    enforcement. EKS-specific V1 CIDR workaround for K8s label SmartGroup
    resolution failure (controller registers EKS as Partial).
    Leave empty ([]) on first apply; populate after MCP servers are deployed.
  EOT
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

variable "copilot_syslog_index" {
  description = "Remote syslog index slot on the Aviatrix Controller (0-9). Must be free; change if another blueprint or config already uses this slot."
  type        = number
  default     = 9
}

# -----------------------------------------------------------------------------
# Naming
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for all resource names created by this blueprint"
  type        = string
  default     = "obot-mcp"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "name_prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}
