# -----------------------------------------------------------------------------
# Pattern C: Prod/Non-Prod + Namespace-as-a-Service — AWS Network Variables
# RECOMMENDED pattern for most organizations
# -----------------------------------------------------------------------------

variable "aws_account_name" {
  description = "Aviatrix AWS account name (as onboarded in Controller). Equivalent to aviatrix_aws_account_name in other patterns."
  type        = string
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-2"
}

# --------------- CIDR Ranges ---------------

variable "transit_cidr" {
  description = "Transit VPC CIDR"
  type        = string
  default     = "10.2.0.0/20"
}

variable "prod_vpc_cidr" {
  description = "Production VPC CIDR"
  type        = string
  default     = "10.10.0.0/20"
}

variable "nonprod_vpc_cidr" {
  description = "Non-production VPC CIDR"
  type        = string
  default     = "10.20.0.0/20"
}

variable "db_spoke_cidr" {
  description = "Database spoke CIDR (prod data only)"
  type        = string
  default     = "10.5.0.0/22"
}

variable "pod_cidr" {
  description = "Secondary CIDR for pod networking (VPC CNI custom networking)"
  type        = string
  default     = "100.64.0.0/16"
}

# --------------- Naming ---------------

variable "environment_prefix" {
  description = "Prefix for all resource names. Equivalent to name_prefix in other patterns."
  type        = string
  default     = "pc2"
}

variable "transit_gw_size" {
  description = "Instance size for Transit Gateway"
  type        = string
  default     = "c5.xlarge"
}

variable "spoke_gw_size" {
  description = "Instance size for Spoke Gateways"
  type        = string
  default     = "c5.xlarge"
}

variable "db_spoke_gw_size" {
  description = "Instance size for DB Spoke Gateway"
  type        = string
  default     = "t3.medium"
}

variable "enable_ha" {
  description = "Enable HA for all gateways"
  type        = bool
  default     = true
}

# --------------- Cluster IDs (populated after cluster layer deploys) ---------------

variable "prod_cluster_id" {
  description = "Aviatrix cluster ID for the production EKS cluster (from K8s resource discovery)"
  type        = string
  default     = ""
}

variable "nonprod_cluster_id" {
  description = "Aviatrix cluster ID for the non-production EKS cluster (from K8s resource discovery)"
  type        = string
  default     = ""
}

# --------------- DNS ---------------

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS resolution"
  type        = string
  default     = ""
}

variable "dns_domain" {
  description = "Base DNS domain for services"
  type        = string
  default     = "internal.example.com"
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
