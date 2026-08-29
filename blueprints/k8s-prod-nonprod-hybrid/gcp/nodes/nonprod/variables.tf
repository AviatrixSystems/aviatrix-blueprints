# -----------------------------------------------------------------------------
# Pattern C: GKE Non-Production Nodes — Variables
# -----------------------------------------------------------------------------

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "environment_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "patternc"
}

variable "cluster_name" {
  description = "GKE non-production cluster name"
  type        = string
}

variable "cluster_endpoint" {
  description = "GKE non-production cluster endpoint"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "GKE non-production cluster CA certificate (base64)"
  type        = string
}

variable "cluster_id" {
  description = "GKE non-production cluster ID for Aviatrix onboarding"
  type        = string
}

variable "dns_zone_name" {
  description = "Cloud DNS private zone name"
  type        = string
}

variable "dns_domain" {
  description = "DNS domain for services"
  type        = string
  default     = "internal.example.com"
}

variable "aviatrix_controller_ip" {
  description = "Aviatrix Controller IP for k8s-firewall"
  type        = string
}

variable "aviatrix_username" {
  description = "Aviatrix Controller username"
  type        = string
}

variable "aviatrix_password" {
  description = "Aviatrix Controller password"
  type        = string
  sensitive   = true
}

variable "controller_ip" {
  description = "IP address or hostname of the Aviatrix Controller"
  type        = string
  default     = null
}

variable "controller_username" {
  description = "Admin username for the Aviatrix Controller"
  type        = string
  default     = "admin"
}

variable "controller_password" {
  description = "Admin password for the Aviatrix Controller"
  type        = string
  sensitive   = true
  default     = null
}

# -----------------------------------------------------------------------------
# Node pool sizing (inline node pool — previously embedded in cluster module)
# -----------------------------------------------------------------------------

variable "node_machine_type" {
  description = "Machine type for the default non-production node pool"
  type        = string
  default     = "e2-standard-2"
}

variable "node_min_count" {
  description = "Minimum node count per zone for the default node pool autoscaler"
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum node count per zone for the default node pool autoscaler"
  type        = number
  default     = 8
}

variable "initial_node_count" {
  description = "Initial number of nodes per zone when the node pool is created"
  type        = number
  default     = 2
}
