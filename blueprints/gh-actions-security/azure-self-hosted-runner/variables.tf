variable "aviatrix_controller_ip" {
  description = "Aviatrix controller hostname (no https://). Set via TF_VAR_aviatrix_controller_ip env var — do NOT commit in tfvars."
  type        = string
  sensitive   = true
}

variable "aviatrix_username" {
  description = "Aviatrix controller username. Set via TF_VAR_aviatrix_username env var — do NOT commit in tfvars."
  type        = string
  sensitive   = true
}

variable "aviatrix_password" {
  description = "Aviatrix controller password. Set via TF_VAR_aviatrix_password env var — do NOT commit in tfvars."
  type        = string
  sensitive   = true
}

variable "azure_subscription_id" {
  description = "Azure subscription ID where all resources are deployed."
  type        = string
}

variable "aviatrix_account_name" {
  description = "Aviatrix-side account name that maps to var.azure_subscription_id."
  type        = string
}

variable "location" {
  description = "Azure region (singleword form, e.g. westeurope, eastus2, centralindia). Display name for Aviatrix vpc_reg is resolved via data.azurerm_location."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to all named resources (resource group, VNet, NSG, DCF groups, etc.)."
  type        = string
  default     = "gh-runner"
}

variable "spoke_gateway_name" {
  description = "Aviatrix spoke gateway name. When null, auto-derived from local.name_prefix so multiple deployments don't collide."
  type        = string
  default     = null
}

variable "vnet_cidr" {
  description = "VNet address space"
  type        = string
  default     = "10.10.10.0/24"
}

variable "gw_subnet_cidr" {
  description = "Aviatrix GW subnet CIDR"
  type        = string
  default     = "10.10.10.0/26"
}

variable "runner_subnet_cidr" {
  description = "Runner VM subnet CIDR"
  type        = string
  default     = "10.10.10.64/26"
}

variable "github_pat" {
  description = "GitHub PAT with repo scope — used at VM boot to generate a fresh runner registration token via API"
  type        = string
  sensitive   = true
}

variable "github_repo_url" {
  description = "GitHub repo URL for runner registration"
  type        = string
}

variable "runner_vm_size" {
  description = "Azure VM size for the runner"
  type        = string
  default     = "Standard_B2s_v2"
}

variable "admin_username" {
  description = "Admin username for runner VM"
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "Password for runner VM admin user (enables serial console access). Set via TF_VAR_admin_password env var — do NOT commit in tfvars."
  type        = string
  sensitive   = true
}

variable "runner_version" {
  description = "GitHub Actions runner version (e.g. 2.334.0)"
  type        = string
  default     = "2.334.0"
}

variable "runner_package_hash" {
  description = "SHA-256 hash of the runner linux-x64 tarball for the specified version"
  type        = string
  default     = "048024cd2c848eb6f14d5646d56c13a4def2ae7ee3ad12122bee960c56f3d271"
}

variable "gh_runner_required_fqdns" {
  description = "FQDNs required by the GitHub Actions runner (HTTPS 443): registration API, runner binary download, Actions service, artifact/cache, container registry, packages."
  type        = list(string)
  default = [
    "github.com",
    "api.github.com",
    "*.actions.githubusercontent.com",
    "objects.githubusercontent.com",
    "codeload.github.com",
    "*.pkg.github.com",
    "ghcr.io",
    "*.ghcr.io",
    "raw.githubusercontent.com",
    "release-assets.githubusercontent.com",
  ]
}

variable "linux_pkg_install_fqdns" {
  description = "Ubuntu APT FQDNs for cloud-init package installation (HTTP 80 + HTTPS 443)."
  type        = list(string)
  default = [
    "archive.ubuntu.com",
    "security.ubuntu.com",
    "esm.ubuntu.com",
    "azure.archive.ubuntu.com",
    "entropy.ubuntu.com",
    "api.snapcraft.io",
  ]
}

variable "tool_call_fqdns" {
  description = "FQDNs the runner is allowed to reach for agent/tool calls (HTTP 80 + HTTPS 443). Set per deployment via tfvars; when empty the corresponding WebGroup and DCF rule are omitted entirely."
  type        = list(string)
  default     = []
}

variable "admin_ssh_public_key" {
  description = "SSH public key for runner VM admin user. Set in tfvars; no default — supply your own key."
  type        = string
}
