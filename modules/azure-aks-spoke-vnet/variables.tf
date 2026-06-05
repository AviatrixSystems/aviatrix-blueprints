variable "name" {
  description = "Base name for the spoke VNet, resource group, and gateway."
  type        = string
}

variable "cluster_name" {
  description = "AKS cluster name, used for subnet/resource tagging."
  type        = string
}

variable "vnet_cidr" {
  description = "Routable /23 CIDR for the VNet (gateway, ingress, node subnets carved from this)."
  type        = string
  default     = "10.30.0.0/23"

  validation {
    condition     = can(cidrhost(var.vnet_cidr, 0)) && tonumber(split("/", var.vnet_cidr)[1]) == 23
    error_message = "vnet_cidr must be a valid IPv4 /23 CIDR block (the subnet layout assumes a /23)."
  }
}

variable "pod_cidr" {
  description = "Dedicated pod subnet CIDR (Azure CNI pod-subnet mode), added as a 2nd VNet address space."
  type        = string
  default     = "100.64.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "pod_cidr must be a valid IPv4 CIDR block."
  }
}

variable "azure_region" {
  description = "Azure region in azurerm form (e.g. eastus2)."
  type        = string
}

variable "aviatrix_azure_region" {
  description = "Azure region in Aviatrix form (e.g. East US 2)."
  type        = string
}

variable "aviatrix_azure_account_name" {
  description = "Name of the Azure access account onboarded in the Aviatrix Controller."
  type        = string
}

variable "transit_type" {
  description = "How the spoke connects to the fabric. 'none' = standalone (Single IP SNAT egress only); 'aviatrix' = attach to an Aviatrix transit gateway."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "aviatrix"], var.transit_type)
    error_message = "transit_type must be one of: none, aviatrix."
  }
}

variable "transit_gw_name" {
  description = "Aviatrix transit gateway name to attach to. Required when transit_type = aviatrix."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}
