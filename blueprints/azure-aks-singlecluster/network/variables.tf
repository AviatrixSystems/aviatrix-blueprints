variable "name_prefix" {
  description = "Prefix for all resources. Also used as the AKS cluster name."
  type        = string
  default     = "aks-single"

  validation {
    condition     = length(var.name_prefix) >= 1 && length(var.name_prefix) <= 20
    error_message = "name_prefix must be 1-20 characters."
  }
}

variable "azure_region" {
  description = "Azure region (azurerm form, e.g. eastus2)."
  type        = string
  default     = "eastus2"
}

variable "aviatrix_azure_region" {
  description = "Azure region (Aviatrix form, e.g. East US 2)."
  type        = string
  default     = "East US 2"
}

variable "aviatrix_azure_account_name" {
  description = "Azure access account name as onboarded in the Aviatrix Controller."
  type        = string
}

variable "vnet_cidr" {
  description = "Routable /23 CIDR for the spoke VNet."
  type        = string
  default     = "10.30.0.0/23"
}

variable "pod_cidr" {
  description = "Dedicated pod subnet CIDR."
  type        = string
  default     = "100.64.0.0/16"
}

variable "transit_type" {
  description = "'none' for standalone (Single IP SNAT egress only) or 'aviatrix' to attach to an Aviatrix transit."
  type        = string
  default     = "none"
}

variable "transit_gw_name" {
  description = "Aviatrix transit gateway name (required when transit_type = aviatrix)."
  type        = string
  default     = ""
}

variable "aviatrix_controller_ip" {
  description = "Aviatrix Controller IP/hostname."
  type        = string
}

variable "aviatrix_username" {
  description = "Aviatrix Controller username."
  type        = string
}

variable "aviatrix_password" {
  description = "Aviatrix Controller password."
  type        = string
  sensitive   = true
}
