# -----------------------------------------------------------------------------
# Pattern C: AKS Production Nodes — Variables
# -----------------------------------------------------------------------------

variable "azure_region" {
  description = "Azure region"
  type        = string
  default     = "East US"
}

variable "resource_group_name" {
  description = "Azure Resource Group name"
  type        = string
}

variable "environment_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "patternc"
}

variable "cluster_name" {
  description = "AKS production cluster name"
  type        = string
}

variable "cluster_id" {
  description = "AKS production cluster ID for Aviatrix onboarding"
  type        = string
}

variable "kube_config" {
  description = "AKS production cluster kubeconfig (raw)"
  type        = string
  sensitive   = true
}

variable "dns_zone_name" {
  description = "Azure Private DNS zone name"
  type        = string
}

variable "dns_zone_resource_group" {
  description = "Resource group of the Private DNS zone"
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity"
  type        = string
}

variable "aviatrix_controller_ip" {
  description = "Aviatrix Controller IP for k8s-firewall"
  type        = string
}

variable "aviatrix_username" {
  description = "Aviatrix Controller username"
  type        = string
}

variable "aviatrix_password" {
  description = "Aviatrix Controller password"
  type        = string
  sensitive   = true
}
