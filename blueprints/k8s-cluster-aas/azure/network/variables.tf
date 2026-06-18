#####################
# Pattern A: Cluster-as-a-Service - Azure Network Variables
#####################

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "caas"
}

variable "aviatrix_azure_account_name" {
  description = "Azure account name as registered in Aviatrix Controller"
  type        = string
}

variable "azure_subscription_id" {
  description = "Azure subscription ID for the azurerm provider"
  type        = string
}

variable "azure_region" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US 2"
}

#####################
# CIDRs
#####################

variable "transit_cidr" {
  description = "CIDR for the Aviatrix transit VNet"
  type        = string
  default     = "10.28.0.0/20"
}

variable "team_a_vnet_cidr" {
  description = "Primary CIDR for team-a AKS VNet"
  type        = string
  default     = "10.30.0.0/20"
}

variable "team_b_vnet_cidr" {
  description = "Primary CIDR for team-b AKS VNet"
  type        = string
  default     = "10.31.0.0/20"
}

variable "team_c_vnet_cidr" {
  description = "Primary CIDR for team-c AKS VNet"
  type        = string
  default     = "10.32.0.0/20"
}

variable "db_vnet_cidr" {
  description = "CIDR for the database spoke VNet"
  type        = string
  default     = "10.35.0.0/22"
}

variable "pod_cidr" {
  description = "Overlay CIDR for pod networking (overlapping across VNets, RFC6598)"
  type        = string
  default     = "100.64.0.0/16"
}

#####################
# DNS
#####################

variable "private_dns_zone_name" {
  description = "Azure Private DNS zone name for internal DNS"
  type        = string
  default     = "azure.aviatrixdemo.local"
}

variable "db_private_ip" {
  description = "Private IP address of the database (for DNS record)"
  type        = string
  default     = "10.35.0.10"
}

variable "random_suffix" {
  description = "Append a random suffix to all resource names for uniqueness. Set to false for deterministic naming."
  type        = bool
  default     = true
}

variable "manage_dcf" {
  description = "Whether this blueprint manages DCF enable/disable lifecycle. Set to false if DCF is pre-enabled by another blueprint or the UI."
  type        = bool
  default     = true
}
