# =============================================================================
# Global / naming
# =============================================================================
variable "name_prefix" {
  description = "Prefix used for AWS and Aviatrix object names. Use a short, unique value per lab or agent class."
  type        = string
  default     = "openclaw-vca"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,29}$", var.name_prefix))
    error_message = "name_prefix must be 3-30 chars, start with a lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "agent_class" {
  description = "Human-readable class for this harness, used in tags and README guidance: coding, research, support, healthcare-phi, hermes, or custom."
  type        = string
  default     = "coding"

  validation {
    condition     = contains(["coding", "research", "support", "healthcare-phi", "hermes", "custom"], var.agent_class)
    error_message = "agent_class must be one of: coding, research, support, healthcare-phi, hermes, custom."
  }
}

variable "aws_region" {
  description = "AWS region for the VPC, gateway, and VM."
  type        = string
  default     = "us-east-1"
}

variable "aws_access_account" {
  description = "Aviatrix access account name for the AWS account."
  type        = string
}

variable "tags" {
  description = "Tags applied to AWS resources."
  type        = map(string)
  default = {
    blueprint = "openclaw-agent-harness-aws"
    owner     = "aviatrix-blueprints"
  }
}

# =============================================================================
# Aviatrix controller and CoPilot
# =============================================================================
variable "controller_ip" {
  description = "Aviatrix Controller IP or DNS name."
  type        = string
}

variable "controller_username" {
  description = "Aviatrix Controller username."
  type        = string
  default     = "admin"
}

variable "controller_password" {
  description = "Aviatrix Controller password. Prefer TF_VAR_controller_password or a secure variable store."
  type        = string
  sensitive   = true
}

variable "copilot_private_ip" {
  description = "Optional CoPilot private IP for remote syslog and association. Leave empty to skip."
  type        = string
  default     = ""
}

variable "copilot_public_ip" {
  description = "Optional CoPilot public IP. Used by the direct association API when public IP visibility is required."
  type        = string
  default     = ""
}

variable "copilot_syslog_index" {
  description = "Remote syslog index used for CoPilot FlowIQ log ingestion."
  type        = number
  default     = 9
}

variable "manage_controller_policy" {
  description = "When true, this blueprint owns the controller-level DCF policy list and POST_RULES default action. Set false when a central platform module merges policy for multiple blueprints on the same Aviatrix Controller."
  type        = bool
  default     = true
}

# =============================================================================
# Network
# =============================================================================
variable "vpc_cidr" {
  description = "CIDR for the OpenClaw agent VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "availability_zone_count" {
  description = "Number of private agent subnets to create. The default single-AZ shape keeps the lab low-cost."
  type        = number
  default     = 1

  validation {
    condition     = var.availability_zone_count >= 1 && var.availability_zone_count <= 3
    error_message = "availability_zone_count must be 1, 2, or 3."
  }
}

variable "private_subnet_newbits" {
  description = "newbits passed to cidrsubnet for private subnets. Default /24s when vpc_cidr is /16."
  type        = number
  default     = 8
}

variable "program_private_default_route" {
  description = "Whether to call the mc-spoke module's enable_private_vpc_default_route. Keep FALSE: with single_ip_snat=true the egress Spoke Gateway already orchestrates the private subnet default route to its own ENI, and the controller rejects enabling both at once (AVXERR-TRANSIT-EDIT-0056)."
  type        = bool
  default     = false
}

variable "create_ssm_vpc_endpoints" {
  description = "Create interface VPC endpoints for SSM, ssmmessages, ec2messages, CloudWatch Logs, and STS. This makes private SSM access reliable even before internet egress policy is tuned."
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Create VPC Flow Logs to CloudWatch for an AWS-native egress audit trail beside CoPilot FlowIQ. Set false in accounts whose SCPs block ec2:DeleteFlowLogs (keeps terraform destroy clean) or where flow logs are managed centrally."
  type        = bool
  default     = true
}

variable "create_s3_gateway_endpoint" {
  description = "Create an S3 gateway endpoint on the private route table for AWS bootstrap/artifact paths that should stay on AWS private networking."
  type        = bool
  default     = true
}

variable "controller_sync_wait" {
  description = "Wait after Spoke Gateway creation before creating Aviatrix SmartGroups/WebGroups. This reduces controller inventory race conditions in newly-created VPCs."
  type        = string
  default     = "45s"
}

# =============================================================================
# Aviatrix Spoke Gateway
# =============================================================================
variable "spoke_gateway_size" {
  description = "Aviatrix Spoke Gateway EC2 instance size."
  type        = string
  default     = "t3.medium"
}

variable "spoke_gateway_name" {
  description = "Optional explicit Aviatrix gateway name. Empty uses name_prefix."
  type        = string
  default     = ""
}

variable "single_ip_snat" {
  description = "Enable single-IP SNAT on the Spoke Gateway. Leave true for the simple lab. Set false before adding Aviatrix TLS decryption in Controller 9.0+ designs."
  type        = bool
  default     = true
}

variable "enable_gateway_volume_encryption" {
  description = "Enable volume encryption for the Aviatrix Spoke Gateway instance when supported by the selected module/provider/controller combination."
  type        = bool
  default     = true
}

variable "enable_tls_decryption_design" {
  description = "Documentation/check flag only. This package does not configure TLS decryption, but this flag prevents accidentally combining the design with single_ip_snat=true."
  type        = bool
  default     = false
}

# =============================================================================
# OpenClaw / Hermes / NemoClaw VM
# =============================================================================
variable "agent_instance_type" {
  description = "EC2 instance type for the private OpenClaw/Hermes/NemoClaw terminal host."
  type        = string
  default     = "t3.large"
}

variable "agent_root_volume_size_gb" {
  description = "Root EBS volume size for the OpenClaw/Hermes/NemoClaw host."
  type        = number
  default     = 80
}

variable "agent_private_ip" {
  description = "Optional static private IP for the OpenClaw VM. Empty lets AWS assign one."
  type        = string
  default     = ""
}

variable "agent_workload_tag_key" {
  description = "CSP tag KEY used to identify the agent workload for the source SmartGroup. The VM is tagged with this key/value, and the SmartGroup matches on it, so policy follows the workload by tag rather than by static CIDR."
  type        = string
  default     = "Role"
}

variable "agent_workload_tag_value" {
  description = "CSP tag VALUE used to identify the agent workload for the source SmartGroup."
  type        = string
  default     = "openclaw-agent-harness"
}

variable "install_mode" {
  description = "Installer script staged onto the VM: none, openclaw, nemoclaw, or hermes. The hermes option runs the NemoClaw installer with NEMOCLAW_AGENT=hermes."
  type        = string
  default     = "nemoclaw"

  validation {
    condition     = contains(["none", "openclaw", "nemoclaw", "hermes"], var.install_mode)
    error_message = "install_mode must be one of: none, openclaw, nemoclaw, hermes."
  }
}

variable "auto_run_installer" {
  description = "When true, cloud-init runs the selected remote installer on first boot. Defaults false so practitioners can review and run via SSM. NemoClaw/Hermes non-interactive install also requires auto_accept_third_party_software=true."
  type        = bool
  default     = false
}

variable "auto_accept_third_party_software" {
  description = "Sets NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1 for non-interactive NemoClaw/Hermes runs. Keep false until your legal/security process approves third-party installers."
  type        = bool
  default     = false
}

variable "install_docker" {
  description = "Install Ubuntu docker.io during cloud-init. NemoClaw can also install Docker, but pre-installing it improves repeatability for non-interactive labs."
  type        = bool
  default     = false
}

variable "install_bootstrap_packages" {
  description = "Run apt-get update/install during first boot to install convenience tools. Defaults false because strict enforce mode may block HTTP-based apt mirrors; enable only in monitor mode or with an approved private package mirror."
  type        = bool
  default     = false
}

# =============================================================================
# DCF policy behavior
# =============================================================================
variable "policy_mode" {
  description = "monitor or enforce. Monitor permits/logs would-be deny traffic; enforce blocks it."
  type        = string
  default     = "monitor"

  validation {
    condition     = contains(["monitor", "enforce"], var.policy_mode)
    error_message = "policy_mode must be monitor or enforce."
  }
}

variable "enable_package_installs" {
  description = "Allow package registry and source-control destinations commonly needed by terminal/coding agents."
  type        = bool
  default     = true
}

variable "enable_public_reference" {
  description = "Allow broad public-reference presets used by more permissive NemoClaw/OpenClaw demo workflows. Keep false for restricted production."
  type        = bool
  default     = false
}

variable "log_permit_rules" {
  description = "Log named permit rules in Aviatrix/CoPilot. Keep true for labs and monitor-first rollout; high-volume production environments may set false after baselining."
  type        = bool
  default     = true
}

variable "openclaw_core_domains" {
  description = "OpenClaw/NemoClaw/Hermes control-plane, installer, and documentation endpoints."
  type        = list(string)
  default = [
    "openclaw.ai",
    "www.openclaw.ai",
    "docs.openclaw.ai",
    "clawhub.ai",
    "www.nvidia.com"
  ]
}

variable "approved_model_gateway_domains" {
  description = "Approved model gateway or provider FQDNs. Prefer an enterprise model gateway; keep direct provider lists small and business-approved."
  type        = list(string)
  default = [
    "integrate.api.nvidia.com",
    "inference-api.nvidia.com"
  ]
}

variable "approved_model_gateway_cidrs" {
  description = "Optional CIDR destinations for internal model gateways. A rule is created only when this list is non-empty."
  type        = list(string)
  default     = []
}

variable "package_registry_domains" {
  description = "Package, source-control, Docker, and artifact destinations needed by terminal/coding agents and NemoClaw/OpenClaw installers. Trim this for production."
  type        = list(string)
  default = [
    "registry.npmjs.org",
    "npmjs.com",
    "nodejs.org",
    "deb.nodesource.com",
    "pypi.org",
    "files.pythonhosted.org",
    "github.com",
    "*.github.com",
    "api.github.com",
    "raw.githubusercontent.com",
    "objects.githubusercontent.com",
    "*.githubusercontent.com",
    "huggingface.co",
    "cdn-lfs.huggingface.co",
    "download.docker.com",
    "get.docker.com",
    "registry-1.docker.io",
    "auth.docker.io",
    "production.cloudflare.docker.com",
    "*.docker.io"
  ]
}

variable "aws_infra_domains" {
  description = "Additional AWS API FQDNs to allow. Region-specific SSM/EC2/STS/S3/ECR endpoints are added automatically in locals."
  type        = list(string)
  default     = []
}

variable "os_update_domains" {
  description = "Optional HTTPS package/update destinations for staged installer workflows. Many Ubuntu apt mirrors still use HTTP, so strict production should prefer private mirrors or baked AMIs."
  type        = list(string)
  default = [
    "archive.ubuntu.com",
    "security.ubuntu.com",
    "*.archive.ubuntu.com",
    "*.ec2.archive.ubuntu.com",
    "changelogs.ubuntu.com"
  ]
}

variable "approved_saas_api_domains" {
  description = "Business SaaS APIs approved for this agent class, for example company.zendesk.com or api.salesforce.com. Empty means no SaaS allow rule is created."
  type        = list(string)
  default     = []
}

variable "approved_mcp_gateway_domains" {
  description = "Approved enterprise MCP or tool gateway FQDNs. Empty means no MCP gateway allow rule is created."
  type        = list(string)
  default     = []
}

variable "identity_and_telemetry_domains" {
  description = "Approved identity-provider and observability endpoints. Empty means no identity/telemetry allow rule is created."
  type        = list(string)
  default     = []
}

variable "public_reference_domains" {
  description = "Optional broad reference presets; only used when enable_public_reference=true."
  type        = list(string)
  default = [
    "brave.com",
    "api.search.brave.com",
    "api.open-meteo.com",
    "geocoding-api.open-meteo.com",
    "api.weather.gov"
  ]
}

variable "unapproved_model_provider_domains" {
  description = "Shadow-model deny list. Remove a domain from this list before adding it to approved_model_gateway_domains. Empty disables the named shadow-model deny rule."
  type        = list(string)
  default = [
    "api.openai.com",
    "api.anthropic.com",
    "generativelanguage.googleapis.com",
    "api.mistral.ai",
    "api.cohere.ai",
    "api.together.xyz",
    "api.fireworks.ai",
    "openrouter.ai",
    "api.openrouter.ai",
    "api.deepseek.com",
    "api.x.ai"
  ]
}

variable "east_west_deny_cidrs" {
  description = "RFC1918 or adjacent-spoke CIDRs denied after explicit allows. Add internal API CIDRs to approved_model_gateway_cidrs or SaaS/MCP FQDNs before broad internal deny."
  type        = list(string)
  default = [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16"
  ]
}
