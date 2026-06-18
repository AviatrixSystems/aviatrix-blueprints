variable "name" {
  description = "Short name for this VPC (e.g., 'frontend', 'backend')"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for subnets"
  type        = string
}

variable "vpc_cidr" {
  description = "Documentation-only aggregate CIDR for the VPC (used in firewall internal source_ranges)"
  type        = string
}

variable "nodes_cidr" {
  description = "Primary CIDR of the GKE node subnet"
  type        = string
}

variable "pods_cidr" {
  description = "Secondary CIDR (alias range) for GKE pod IPs"
  type        = string
}

variable "services_cidr" {
  description = "Secondary CIDR (alias range) for GKE Services"
  type        = string
}

variable "avx_gw_cidr" {
  description = "CIDR for the dedicated Aviatrix spoke gateway subnet (/28 is enough)"
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "GKE control-plane CIDR (/28). Added to internal firewall source_ranges so nodes can talk to the master."
  type        = string
  default     = null
}

variable "create_proxy_only_subnet" {
  description = "Reserve a regional proxy-only subnet for GCP-managed L7 ALBs (Gateway API)"
  type        = bool
  default     = true
}

variable "proxy_only_cidr" {
  description = "CIDR for the regional proxy-only subnet (must not overlap nodes/pods/services)"
  type        = string
  default     = ""
}
