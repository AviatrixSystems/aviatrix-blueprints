# ── Locals ───────────────────────────────────────────────────────────────────

locals {
  suffix = tostring(random_integer.suffix.result)

  tags = {
    blueprint = "secured-ai-foundry"
  }

  private_dns_zones = [
    "privatelink.cognitiveservices.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.services.ai.azure.com",
    "privatelink.blob.core.windows.net",
    "privatelink.search.windows.net",
    "privatelink.documents.azure.com",
  ]

  sg_any             = "def000ad-0000-0000-0000-000000000000"
  sg_public_internet = "def000ad-0000-0000-0000-000000000001"
  sg_threat_intel    = "def05854-4100-0000-0000-000000000000"

  wg_allweb = "def000ad-0000-0000-0000-000000000002"
}

# ── Azure provider variables ──────────────────────────────────────────────────

variable "location" {
  description = "Azure region — must be an Azure AI Foundry supported region"
  type        = string
  default     = "francecentral"

  validation {
    condition = contains([
      "eastus", "eastus2", "westus", "westus3",
      "northcentralus", "southcentralus",
      "westeurope", "northeurope", "francecentral",
      "uksouth", "swedencentral",
      "australiaeast", "japaneast",
      "southeastasia", "canadacentral", "canadaeast",
      "brazilsouth", "koreacentral",
    ], var.location)
    error_message = "Region not supported by Azure AI Foundry. See https://learn.microsoft.com/azure/ai-foundry/reference/region-support"
  }
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
  default     = "foundry-sec-network-rg"
}

variable "vnet_name" {
  description = "VNet base name (random suffix appended)"
  type        = string
  default     = "vnet-foundry"
}

variable "vnet_address_space" {
  description = "VNet address space — must be at least /23 to accommodate all subnets"
  type        = string
  default     = "10.11.0.0/23"
}


variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

# ── Aviatrix provider variables ──────────────────────────────────────────────

variable "avx_controller_ip" {
  description = "Aviatrix controller FQDN or IP"
  type        = string
}

variable "avx_username" {
  description = "Aviatrix controller admin username"
  type        = string
}

variable "avx_password" {
  description = "Aviatrix controller admin password"
  type        = string
  sensitive   = true
}

# ── Aviatrix spoke gateway variables ─────────────────────────────────────────

variable "avx_account_name" {
  description = "Aviatrix access account name for the Azure subscription"
  type        = string
}

variable "avx_gw_name" {
  description = "Aviatrix spoke gateway name"
  type        = string
  default     = "avx-spoke-foundry"
}

variable "avx_gw_size" {
  description = "Azure VM size for the spoke gateway"
  type        = string
  default     = "Standard_B2ms"
}

variable "avx_transit_gw_name" {
  description = "Name of the Aviatrix transit gateway to attach to. Set to 'donotattach' to skip."
  type        = string
  default     = "donotattach"
}

# ── DCF policy variables ──────────────────────────────────────────────────────

variable "aca_requirements_fqdns" {
  description = "FQDNs required for ACA runtime — permitted without TLS decryption. Defaults are the Microsoft-published ACA firewall requirements."
  type        = list(string)
  default = [
    "mcr.microsoft.com",
    "*.data.mcr.microsoft.com",
    "packages.aks.azure.com",
    "acs-mirror.azureedge.net",
    "*.identity.azure.net",
    "login.microsoftonline.com",
    "*.login.microsoftonline.com",
    "*.login.microsoft.com",
    "login.microsoft.com",
    "*.in.applicationinsights.azure.com",
  ]
}

variable "aca_platform_svc_tags" {
  description = "Azure service tags for ACA platform control-plane — permitted without TLS decryption."
  type        = list(string)
  default = [
    "AzureActiveDirectory",
    "MicrosoftContainerRegistry",
    "AzureFrontDoorFirstParty",
    "AzureContainerRegistry",
  ]
}

variable "tool_call_fqdns" {
  description = "List of FQDNs approved for agent tool calls — TLS-decrypted and inspected. Add sanctioned MCP server endpoints and external APIs here."
  type        = list(string)
  default     = ["api.ipify.org"]
}
