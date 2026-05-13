variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy the VM into"
  type        = string
}

variable "location" {
  description = "Azure region in azurerm format (e.g., 'eastus2')"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the VM's NIC"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
