#####################
# Pattern B: Namespace-as-a-Service — AWS Network Variables
#
# Single shared EKS cluster. All teams share one VPC and one spoke gateway.
# Isolation is enforced by DCF SmartGroups keyed on k8s_namespace.
#####################

variable "name_prefix" {
  description = "Prefix for all resource names (enables multiple deployments in the same account)"
  type        = string
  default     = "naas"
}

variable "aviatrix_aws_account_name" {
  description = "AWS account name as registered in Aviatrix Controller"
  type        = string
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment name (e.g. prod, staging)"
  type        = string
  default     = "prod"
}

#####################
# CIDRs
#####################

variable "transit_cidr" {
  description = "CIDR for the Aviatrix transit VPC"
  type        = string
  default     = "10.2.0.0/20"
}

variable "shared_vpc_cidr" {
  description = "CIDR for the shared cluster VPC (all teams share this single VPC)"
  type        = string
  default     = "10.10.0.0/16"
}

variable "pod_cidr" {
  description = "Secondary CIDR for pod networking (VPC CNI custom networking, RFC6598)"
  type        = string
  default     = "100.64.0.0/16"
}

#####################
# DNS
#####################

variable "private_dns_zone_name" {
  description = "Route53 private hosted zone domain name"
  type        = string
  default     = "aws-naas.aviatrixdemo.local"
}

#####################
# DCF
#####################

variable "k8s_cluster_suffix" {
  description = "Suffix for the shared EKS cluster name (appended to name_prefix)"
  type        = string
  default     = "shared-eks"
}

variable "team_namespaces" {
  description = "List of team namespace names for SmartGroup creation"
  type        = list(string)
  default     = ["team-a", "team-b", "team-c"]
}

variable "geo_block_countries" {
  description = "ISO country codes to geo-block"
  type        = list(string)
  default     = ["CN", "RU", "KP", "IR"]
}

variable "approved_web_domains" {
  description = "Domains permitted for namespace egress via WebGroups"
  type        = list(string)
  default = [
    "*.amazonaws.com",
    "registry.npmjs.org",
    "pypi.org",
    "ghcr.io",
    # Calico image registry
    "docker.io",
    "*.docker.io",
    "quay.io",
  ]
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
