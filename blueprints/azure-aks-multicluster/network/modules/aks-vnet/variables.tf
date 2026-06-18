variable "name" {
  description = "Short name for the VNet (e.g., 'frontend', 'backend')"
  type        = string
}

variable "cluster_name" {
  description = "Full AKS cluster name, used for resource tagging"
  type        = string
}

variable "vnet_cidr" {
  description = "Primary (routable) CIDR for the VNet — node, system, and Aviatrix GW subnets are carved from this."
  type        = string
}

variable "pod_cidr" {
  description = <<-EOT
    Pod CIDR added as a SECOND VNet address space (e.g., 100.64.0.0/16). AKS allocates
    pod IPs from this subnet directly (pod-subnet mode, not overlay), so pod IPs are real
    VNet addresses and traverse the Azure network plane natively. Both clusters use the
    same value (overlapping by design — VNets are isolated from each other; the Aviatrix
    spoke GW SNATs pod CIDR to its own private IP for transit, sidestepping the overlap).
  EOT
  type        = string
}

variable "region" {
  description = "Azure region in azurerm format (e.g., 'eastus2')"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
