# ── Locals ───────────────────────────────────────────────────────────────────

locals {
  suffix            = data.terraform_remote_state.network.outputs.suffix
  vnet_name         = data.terraform_remote_state.network.outputs.vnet_name
  vnet_resource_group = data.terraform_remote_state.network.outputs.resource_group_name

  tags = {
    blueprint = "secured-ai-foundry"
  }
}

# ── Provider variables (cannot be sourced from remote state) ─────────────────

variable "subscription_id" {
  description = "Azure subscription ID containing the foundry VNet"
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

# ── Aviatrix VPN gateway variables ───────────────────────────────────────────

variable "avx_account_name" {
  description = "Aviatrix access account name for the Azure subscription"
  type        = string
}

variable "avx_vpn_gw_name" {
  description = "Aviatrix VPN gateway base name (random 4-digit suffix appended)"
  type        = string
  default     = "avx-vpn-foundry"
}

variable "avx_vpn_gw_size" {
  description = "Azure VM size for the VPN gateway"
  type        = string
  default     = "Standard_B2ms"
}

variable "foundry_vnet_cidr" {
  description = "Foundry VNet address space — the only CIDR routed through the VPN tunnel (split tunnel). Must match network-infra vnet_address_space."
  type        = string
  default     = "10.11.0.0/23"
}

variable "vpn_gw_subnet_cidr" {
  description = "CIDR for the new VPN gateway subnet — must fit in the foundry VNet and must not overlap with existing subnets."
  type        = string
  default     = "10.11.0.32/28"
}

variable "vpn_client_cidr" {
  description = "IP pool assigned to VPN clients — must not overlap with foundry_vnet_cidr or any on-prem CIDRs"
  type        = string
  default     = "192.168.43.0/24"
}

# ── VPN user variables ────────────────────────────────────────────────────────

variable "vpn_user_email" {
  description = "Email address of the VPN user — Aviatrix sends the OVPN profile to this address"
  type        = string
}
