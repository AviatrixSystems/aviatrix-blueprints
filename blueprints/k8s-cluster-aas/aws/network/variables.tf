#####################
# Pattern A: Cluster-as-a-Service - AWS Network Variables
#
# Each team gets a dedicated EKS cluster in its own VPC with its own
# Aviatrix Spoke Gateway. DCF uses VPC-level SmartGroups for inter-team isolation.
#####################

variable "name_prefix" {
  description = "Prefix for all resource names (enables multiple deployments in the same account)"
  type        = string
  default     = "caas"
}

variable "aviatrix_aws_account_name" {
  description = "AWS account name as registered in Aviatrix Controller"
  type        = string
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

#####################
# CIDRs
#####################

variable "transit_cidr" {
  description = "CIDR for the Aviatrix transit VPC"
  type        = string
  default     = "10.2.0.0/20"
}

variable "team_a_vpc_cidr" {
  description = "Primary CIDR for team-a EKS VPC"
  type        = string
  default     = "10.10.0.0/20"
}

variable "team_b_vpc_cidr" {
  description = "Primary CIDR for team-b EKS VPC"
  type        = string
  default     = "10.11.0.0/20"
}

variable "team_c_vpc_cidr" {
  description = "Primary CIDR for team-c EKS VPC"
  type        = string
  default     = "10.12.0.0/20"
}

variable "db_vpc_cidr" {
  description = "CIDR for the database spoke VPC"
  type        = string
  default     = "10.5.0.0/22"
}

variable "pod_cidr" {
  description = "Overlay CIDR for pod networking (overlapping across VPCs, RFC6598)"
  type        = string
  default     = "100.64.0.0/16"
}

#####################
# DNS
#####################

variable "private_dns_zone_name" {
  description = "Route53 private hosted zone domain name"
  type        = string
  default     = "aws.aviatrixdemo.local"
}

variable "db_private_ip" {
  description = "Private IP address of the database (for DNS record)"
  type        = string
  default     = "10.5.0.10"
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
