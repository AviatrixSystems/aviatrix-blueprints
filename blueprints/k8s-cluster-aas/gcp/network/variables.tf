#####################
# Pattern A: Cluster-as-a-Service - GCP Network Variables
#####################

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "caas"
}

variable "aviatrix_gcp_account_name" {
  description = "GCP account name as registered in Aviatrix Controller"
  type        = string
}

variable "gcp_project" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
}

#####################
# CIDRs
#####################

variable "transit_cidr" {
  description = "CIDR for the Aviatrix transit VPC"
  type        = string
  default     = "10.38.0.0/20"
}

variable "team_a_vpc_cidr" {
  description = "Primary CIDR for team-a GKE VPC"
  type        = string
  default     = "10.40.0.0/20"
}

variable "team_b_vpc_cidr" {
  description = "Primary CIDR for team-b GKE VPC"
  type        = string
  default     = "10.41.0.0/20"
}

variable "team_c_vpc_cidr" {
  description = "Primary CIDR for team-c GKE VPC"
  type        = string
  default     = "10.42.0.0/20"
}

variable "db_vpc_cidr" {
  description = "CIDR for the database spoke VPC"
  type        = string
  default     = "10.45.0.0/22"
}

variable "pod_cidr" {
  description = "Secondary range for pod networking (overlapping across VPCs, RFC6598)"
  type        = string
  default     = "100.64.0.0/16"
}

variable "services_cidr" {
  description = "Secondary range for Kubernetes services"
  type        = string
  default     = "172.40.0.0/20"
}

#####################
# GKE Master CIDRs (must be unique per cluster)
#####################

variable "team_a_master_cidr" {
  description = "CIDR block for team-a GKE master (must be /28, unique per cluster)"
  type        = string
  default     = "172.16.0.0/28"
}

variable "team_b_master_cidr" {
  description = "CIDR block for team-b GKE master (must be /28, unique per cluster)"
  type        = string
  default     = "172.16.0.16/28"
}

variable "team_c_master_cidr" {
  description = "CIDR block for team-c GKE master (must be /28, unique per cluster)"
  type        = string
  default     = "172.16.0.32/28"
}

#####################
# DNS
#####################

variable "dns_private_zone_name" {
  description = "Cloud DNS private zone name for internal DNS"
  type        = string
  default     = "gcp.aviatrixdemo.local"
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
