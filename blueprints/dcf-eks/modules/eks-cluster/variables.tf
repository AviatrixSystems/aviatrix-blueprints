variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.34"
}

variable "vpc_id" {
  description = "VPC ID where EKS cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for EKS control plane ENIs and node groups (infrastructure subnets)"
  type        = list(string)
}

variable "pod_subnet_ids" {
  description = "Subnet IDs for EKS pods (from secondary CIDR, used in ENIConfig)"
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones corresponding to pod_subnet_ids (e.g., ['us-east-2a', 'us-east-2b'])"
  type        = list(string)
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

# Node group configuration has been moved to the eks-node-group module
# This module now only creates the EKS control plane

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

variable "route53_zone_id" {
  description = "Route53 private hosted zone ID for ExternalDNS"
  type        = string
  default     = ""
}

variable "route53_zone_name" {
  description = "Route53 private hosted zone name for ExternalDNS"
  type        = string
  default     = ""
}

variable "enable_aviatrix_onboarding" {
  description = "Enable registration of the EKS cluster with Aviatrix Controller for Smart Groups"
  type        = bool
  default     = true
}

variable "aviatrix_controller_role_arn" {
  description = "IAM role ARN used by Aviatrix Controller to access EKS clusters (e.g., arn:aws:iam::ACCOUNT:role/aviatrix-role-app)"
  type        = string
  default     = ""
}
