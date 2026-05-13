# =============================================================================
# Input Variables
# =============================================================================

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

variable "arm_account_name" {
  description = "Aviatrix access account name for Azure (onboarded in the Controller)"
  type        = string
}

variable "copilot_private_ip" {
  description = "CoPilot private IP — used for syslog stream configuration"
  type        = string
}

variable "copilot_public_ip" {
  description = "CoPilot public IP — required for spoke gateway OTEL exporters (TCP 31284) when the spoke VNet is not peered to the controlplane VNet. Without this, DCF Monitor logs stay empty even though FlowIQ works."
  type        = string
}

# -----------------------------------------------------------------------------
# Azure Subscription + Location
# -----------------------------------------------------------------------------

variable "azure_subscription_id" {
  description = "Azure subscription ID where resources will be created"
  type        = string
}

variable "azure_location" {
  description = "Azure region for all resources (e.g. 'UK South')"
  type        = string
}

# -----------------------------------------------------------------------------
# Resource Group + VNet (created by this blueprint)
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the Azure resource group to create"
  type        = string
  default     = "obot-mcp-rg"
}

variable "vnet_address_space" {
  description = "Address space for the VNet created by this blueprint"
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnet_address_space, 0))
    error_message = "vnet_address_space must be a valid CIDR block."
  }
}

# -----------------------------------------------------------------------------
# AKS Cluster (created by this blueprint)
# -----------------------------------------------------------------------------

variable "aks_subnet_cidr" {
  description = "CIDR for the AKS node subnet. Must be within vnet_address_space and large enough for pod IPs with Azure CNI (each pod consumes one VNet IP). /20 = 4094 IPs."
  type        = string
  default     = "10.1.0.0/20"

  validation {
    condition     = can(cidrhost(var.aks_subnet_cidr, 0))
    error_message = "aks_subnet_cidr must be a valid CIDR block."
  }
}

variable "aks_vm_size" {
  description = "Azure VM size for AKS nodes"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "aks_node_count" {
  description = "Number of AKS nodes"
  type        = number
  default     = 2
}

variable "aks_service_cidr" {
  description = "CIDR for Kubernetes services. Must not overlap with vnet_address_space or aks_subnet_cidr."
  type        = string
  default     = "172.16.0.0/17"
}

variable "aks_dns_service_ip" {
  description = "IP address for the Kubernetes DNS service. Must be within aks_service_cidr."
  type        = string
  default     = "172.16.0.10"
}

# -----------------------------------------------------------------------------
# Spoke Gateway
# -----------------------------------------------------------------------------

variable "spoke_gateway_subnet_cidr" {
  description = "CIDR for the Aviatrix spoke gateway subnet. Must be within vnet_address_space and must not overlap with aks_subnet_cidr. A /26 is sufficient."
  type        = string
  default     = "10.1.200.0/26"

  validation {
    condition     = can(cidrhost(var.spoke_gateway_subnet_cidr, 0))
    error_message = "spoke_gateway_subnet_cidr must be a valid CIDR block."
  }
}

variable "spoke_gateway_size" {
  description = "Azure VM size for the Aviatrix spoke gateway"
  type        = string
  default     = "Standard_B2ms"
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

variable "obot_namespace" {
  description = "Kubernetes namespace for Obot"
  type        = string
  default     = "obot-system"
}

variable "obot_mcp_namespace" {
  description = "Kubernetes namespace where Obot deploys MCP server pods. DCF SmartGroup and FirewallPolicy CRDs target this namespace."
  type        = string
  default     = "obot-mcp"
}

variable "obot_admin_password" {
  description = "Obot admin password"
  type        = string
  sensitive   = true
}

variable "obot_system_pod_cidrs" {
  description = <<-EOT
    List of /32 CIDRs for obot-system pods. Used to scope Obot-specific
    egress permits (Anthropic, GitHub, charts.obot.ai) to the orchestration
    layer only, preventing obot-mcp pods from inheriting them.

    TWO-STEP DEPLOY: Leave empty ([]) on first apply. After Obot is running,
    get pod IPs with:
      kubectl get pods -n <obot_namespace> -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}'
    Then re-apply with those IPs as /32 CIDRs.

    Workaround for Aviatrix V1 policy list limitation: V1 does not support
    k8s namespace SmartGroups as source — only CIDR SmartGroups are valid.
    Update these values when obot-system pods restart.
  EOT
  type        = list(string)
  default     = []
}

variable "npc_chart_version" {
  description = "Version of the aviatrix-network-policy-controller Helm chart from charts.obot.ai. Update when Aviatrix releases a new NPC chart version."
  type        = string
  default     = "v0.0.1"
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
