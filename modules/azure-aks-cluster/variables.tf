variable "cluster_name" {
  description = "AKS cluster name."
  type        = string
}

variable "azure_region" {
  description = "Azure region (azurerm form, e.g. eastus2)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create the AKS cluster in (the spoke VNet's RG)."
  type        = string
}

variable "vnet_id" {
  description = "Spoke VNet resource ID (for the AKS identity Network Contributor role)."
  type        = string
}

variable "node_subnet_id" {
  description = "Subnet ID for AKS node VMs."
  type        = string
}

variable "pod_subnet_id" {
  description = "Subnet ID for AKS pods (pod-subnet mode)."
  type        = string
}

variable "node_route_table_id" {
  description = "Node route table ID (for the AKS identity Network Contributor role)."
  type        = string
}

variable "pod_route_table_id" {
  description = "Pod route table ID (for the AKS identity Network Contributor role)."
  type        = string
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version."
  type        = string
  default     = "1.33"
}

variable "node_pool_config" {
  description = "System/user node pool sizing."
  type = object({
    node_count = number
    min_count  = number
    max_count  = number
    vm_size    = string
  })
  default = {
    node_count = 2
    min_count  = 1
    max_count  = 3
    vm_size    = "Standard_B2s"
  }
}

variable "service_cidr" {
  description = "Kubernetes service CIDR (must not overlap VNet or pod CIDR)."
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "Kubernetes DNS service IP (within service_cidr)."
  type        = string
  default     = "172.16.0.10"
}

variable "authorized_ip_ranges" {
  description = "Extra CIDRs allowed to reach the AKS API server. The spoke GW public IP and (optionally) controller IP are appended automatically."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "spoke_gateway_public_ip" {
  description = "Spoke gateway public IP, appended to AKS API authorized_ip_ranges so node CSE bootstrap succeeds."
  type        = string
}

variable "enable_aviatrix_onboarding" {
  description = "Register the AKS cluster with the Aviatrix Controller for K8s SmartGroups."
  type        = bool
  default     = true
}

variable "aviatrix_controller_public_ip" {
  description = "Controller public egress IP, appended to AKS API authorized_ip_ranges when onboarding."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}
