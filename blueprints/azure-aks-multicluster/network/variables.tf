variable "name_prefix" {
  description = "Prefix for all resource names (e.g., 'aks-demo')"
  type        = string
  default     = "aks-demo"
}

# Aviatrix Controller credentials. These are referenced by the aviatrix
# provider block so `terraform validate` passes without env vars set. At
# plan/apply time, leave them empty in tfvars and export the standard
# AVIATRIX_CONTROLLER_IP / AVIATRIX_USERNAME / AVIATRIX_PASSWORD env vars.

variable "aviatrix_controller_ip" {
  description = "Aviatrix Controller IP/hostname (or set AVIATRIX_CONTROLLER_IP env var)"
  type        = string
  default     = null
}

variable "aviatrix_username" {
  description = "Aviatrix Controller username (or set AVIATRIX_USERNAME env var)"
  type        = string
  default     = null
}

variable "aviatrix_password" {
  description = "Aviatrix Controller password (or set AVIATRIX_PASSWORD env var)"
  type        = string
  sensitive   = true
  default     = null
}

variable "aviatrix_azure_account_name" {
  description = "Aviatrix access account name for Azure (configured in Aviatrix Controller)"
  type        = string
}

variable "azure_region" {
  description = "Azure region for azurerm resources (e.g., 'eastus2')"
  type        = string
  default     = "eastus2"
}

variable "aviatrix_azure_region" {
  description = "Azure region in Aviatrix format (e.g., 'East US 2')"
  type        = string
  default     = "East US 2"
}

variable "transit_cidr" {
  description = "CIDR for the Aviatrix Transit VNet"
  type        = string
  default     = "10.2.0.0/20"
}

variable "frontend_vnet_cidr" {
  description = "Primary CIDR for the frontend AKS VNet"
  type        = string
  default     = "10.10.0.0/23"
}

variable "backend_vnet_cidr" {
  description = "Primary CIDR for the backend AKS VNet"
  type        = string
  default     = "10.20.0.0/23"
}

variable "db_vnet_cidr" {
  description = "CIDR for the DB test VNet"
  type        = string
  default     = "10.5.0.0/22"
}

variable "pod_cidr" {
  description = <<-EOT
    Cilium overlay CIDR for pod IPs — same across all clusters (overlapping by design).
    Aviatrix spoke gateways SNAT this range to the spoke GW IP before sending to transit,
    allowing overlapping pod CIDRs across clusters.
  EOT
  type        = string
  default     = "100.64.0.0/16"
}

variable "service_cidr" {
  description = "Kubernetes service CIDR (must not overlap with VNet or pod CIDR)"
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for the Kubernetes DNS service (must be within service_cidr)"
  type        = string
  default     = "172.16.0.10"
}

variable "private_dns_zone_name" {
  description = "Azure Private DNS zone name for service discovery"
  type        = string
  default     = "azure.aviatrixdemo.local"
}
