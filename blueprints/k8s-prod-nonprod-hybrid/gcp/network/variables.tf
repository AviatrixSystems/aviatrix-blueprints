# -----------------------------------------------------------------------------
# Pattern C: Prod/Non-Prod + Namespace-as-a-Service — GCP Network Variables
# RECOMMENDED pattern for most organizations
# -----------------------------------------------------------------------------

variable "aviatrix_controller_ip" {
  description = "Aviatrix Controller IP or hostname"
  type        = string
}

variable "aviatrix_username" {
  description = "Aviatrix Controller admin username"
  type        = string
}

variable "aviatrix_password" {
  description = "Aviatrix Controller admin password"
  type        = string
  sensitive   = true
}

variable "gcp_account_name" {
  description = "Aviatrix GCP account name (as onboarded in Controller)"
  type        = string
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
}

# --------------- CIDR Ranges ---------------

variable "transit_cidr" {
  description = "Transit VPC CIDR"
  type        = string
  default     = "10.38.0.0/20"
}

variable "prod_vpc_cidr" {
  description = "Production VPC CIDR"
  type        = string
  default     = "10.40.0.0/20"
}

variable "nonprod_vpc_cidr" {
  description = "Non-production VPC CIDR"
  type        = string
  default     = "10.41.0.0/20"
}

variable "db_spoke_cidr" {
  description = "Database spoke CIDR (prod data only)"
  type        = string
  default     = "10.45.0.0/22"
}

variable "pod_cidr" {
  description = "Pod CIDR for VPC-native clusters"
  type        = string
  default     = "100.64.0.0/16"
}

# --------------- Naming ---------------

variable "environment_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "pc-gcp"
}

variable "transit_gw_size" {
  description = "Instance size for Transit Gateway"
  type        = string
  default     = "n1-standard-4"
}

variable "spoke_gw_size" {
  description = "Instance size for Spoke Gateways"
  type        = string
  default     = "n1-standard-4"
}

variable "db_spoke_gw_size" {
  description = "Instance size for DB Spoke Gateway"
  type        = string
  default     = "n1-standard-2"
}

variable "enable_ha" {
  description = "Enable HA for all gateways"
  type        = bool
  default     = true
}

# --------------- DNS ---------------

variable "dns_domain" {
  description = "Base DNS domain for services"
  type        = string
  default     = "internal.example.com"
}

# --------------- Cluster IDs ---------------

variable "prod_cluster_id" {
  description = "Aviatrix cluster ID for the production cluster (from K8s resource discovery)"
  type        = string
  default     = ""
}

variable "nonprod_cluster_id" {
  description = "Aviatrix cluster ID for the non-production cluster (from K8s resource discovery)"
  type        = string
  default     = ""
}

# --------------- Teams ---------------

variable "teams" {
  description = "Map of team names to their configuration"
  type = map(object({
    prod_namespace    = string
    nonprod_namespace = string
    contact           = optional(string, "")
  }))
  default = {
    team-a = {
      prod_namespace    = "team-a-prod"
      nonprod_namespace = "team-a-dev"
    }
    team-b = {
      prod_namespace    = "team-b-prod"
      nonprod_namespace = "team-b-staging"
    }
  }
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
