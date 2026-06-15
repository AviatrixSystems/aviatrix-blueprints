variable "aviatrix_controller_ip" {
  description = "Aviatrix controller hostname or IP (no https://). TF_VAR_aviatrix_controller_ip env var preferred."
  type        = string
  sensitive   = true
}

variable "aviatrix_username" {
  description = "Aviatrix controller username. TF_VAR_aviatrix_username env var preferred."
  type        = string
  sensitive   = true
}

variable "aviatrix_password" {
  description = "Aviatrix controller password. TF_VAR_aviatrix_password env var preferred."
  type        = string
  sensitive   = true
}

variable "aviatrix_sp_object_id" {
  description = "Object ID of the Aviatrix Azure service principal (needs AKS Cluster User Role for CSP-credential onboarding)."
  type        = string
}

variable "azure_subscription_id" {
  description = "Azure subscription ID where the AKS cluster + spoke VNet are deployed."
  type        = string
}

variable "aviatrix_account_name" {
  description = "Aviatrix-side account name that maps to var.azure_subscription_id."
  type        = string
}

variable "location" {
  description = "Azure region in singleword form (e.g. westeurope, centralindia). Aviatrix vpc_reg derived via data.azurerm_location."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to all named resources. A 6-digit deployment ID is auto-appended."
  type        = string
  default     = "gh-aks-runner"
}

variable "spoke_gateway_name" {
  description = "Aviatrix spoke gateway name. When null, auto-derived from local.name_prefix."
  type        = string
  default     = null
}

variable "vnet_cidr" {
  description = "Spoke VNet address space."
  type        = string
  default     = "10.10.30.0/24"
}

variable "gw_subnet_cidr" {
  description = "Aviatrix spoke gateway subnet CIDR."
  type        = string
  default     = "10.10.30.0/26"
}

variable "aks_subnet_cidr" {
  description = "AKS subnet CIDR — sized for nodes + pods (Azure CNI gives every pod a VNet IP)."
  type        = string
  default     = "10.10.30.128/25"
}

variable "spoke_gw_size" {
  description = "Azure VM size for the Aviatrix spoke gateway."
  type        = string
  default     = "Standard_B2ms"
}

variable "aks_node_count" {
  description = "Initial node count for the AKS default node pool. Lab default: 1."
  type        = number
  default     = 1
}

variable "aks_node_vm_size" {
  description = "Azure VM size for AKS default node pool nodes. Lab default: Standard_B2s_v2 (2 vCPU / 8 GB, x86 v2 family — cheap + plenty of RAM for system pods)."
  type        = string
  default     = "Standard_B2s_v2"
}

variable "aks_kubernetes_version" {
  description = "Kubernetes version. When null, AKS picks the default for the region."
  type        = string
  default     = null
}

variable "aks_service_cidr" {
  description = "ClusterIP service CIDR — must not overlap with var.vnet_cidr."
  type        = string
  default     = "10.100.0.0/16"
}

variable "aks_dns_service_ip" {
  description = "DNS service IP (must sit inside aks_service_cidr; commonly the .10 of that range)."
  type        = string
  default     = "10.100.0.10"
}

variable "github_pat" {
  description = "GitHub PAT with repo scope — used by ARC to register runners. Set via tfvars; do not commit."
  type        = string
  sensitive   = true
}

variable "github_repo_url" {
  description = "GitHub repository URL for ARC runner scale set registration (e.g. https://github.com/org/repo)."
  type        = string
}

variable "gh_runner_required_fqdns" {
  description = "FQDNs required by ARC + GitHub Actions runner pods (HTTPS 443)."
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

variable "tool_call_fqdns" {
  description = "FQDNs runner pods may reach for agent/tool calls (HTTP 80 + HTTPS 443). When empty, the DCF rule is omitted."
  type        = list(string)
  default     = []
}

variable "aviatrix_mitm_ca_pem" {
  description = "PEM-encoded Aviatrix MITM CA certificate. Mounted into the TLS-decrypt probe pod so curl trusts GW-resigned certificates. Fetch once: GET https://<controller>/v2.5/api/mitm/ca with Authorization: cid <token>. Required only when deploy_probes=true."
  type        = string
  default     = ""
}

variable "arc_runner_name" {
  description = "ARC runner scale set name — becomes the runs-on label in workflows. Must be unique per controller/repo."
  type        = string
  default     = "azure-arc"
}

variable "deploy_probes" {
  description = "Deploy TLS-probe and ipify-probe pods. Set false to skip probe workloads (e.g. initial infra validation)."
  type        = bool
  default     = true
}
