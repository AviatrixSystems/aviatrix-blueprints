variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "zone" {
  description = "GCP zone for the VM"
  type        = string
}

variable "subnet_id" {
  description = "Self-link of the subnet to deploy the VM into"
  type        = string
}

variable "machine_type" {
  description = "Compute machine type"
  type        = string
  default     = "e2-small"
}

variable "dns_zone_name" {
  description = "Private DNS zone (used in the index.html banner)"
  type        = string
}

variable "service_account_email" {
  description = "Service account attached to the VM (use the project default compute SA if unsure)"
  type        = string
  default     = null
}
