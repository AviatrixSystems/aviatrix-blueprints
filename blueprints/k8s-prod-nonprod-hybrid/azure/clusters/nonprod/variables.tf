# -----------------------------------------------------------------------------
# Pattern C: AKS Non-Production Cluster — Variables
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

variable "kubernetes_version" {
  description = "AKS Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "vnet_id" {
  description = "ARM VNet resource ID for non-production"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for AKS nodes"
  type        = string
}

variable "pod_cidr" {
  description = "Pod CIDR for Azure CNI Overlay"
  type        = string
  default     = "100.64.0.0/16"
}

variable "node_vm_size" {
  description = "VM size for the default node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "node_min_count" {
  type    = number
  default = 2
}

variable "node_max_count" {
  type    = number
  default = 8
}
