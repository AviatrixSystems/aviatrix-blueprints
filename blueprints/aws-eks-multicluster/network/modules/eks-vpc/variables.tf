variable "name" {
  description = "Name prefix for VPC resources"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name for tagging subnets"
  type        = string
}

variable "primary_cidr" {
  description = "Primary CIDR for infrastructure (e.g., 10.10.0.0/23)"
  type        = string

  validation {
    condition     = can(cidrhost(var.primary_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block."
  }
}

variable "secondary_cidr" {
  description = "Secondary CIDR for pods (e.g., 100.64.0.0/16). Can overlap across VPCs."
  type        = string
  default     = "100.64.0.0/16"

  validation {
    condition     = can(cidrhost(var.secondary_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block."
  }
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
