# -----------------------------------------------------------------------------
# Pattern C: GKE Production Nodes — Variables
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
  description = "GKE production cluster name"
  type        = string
}

variable "cluster_endpoint" {
  description = "GKE production cluster endpoint"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "GKE production cluster CA certificate (base64)"
  type        = string
}

variable "cluster_id" {
  description = "GKE production cluster ID for Aviatrix onboarding"
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
