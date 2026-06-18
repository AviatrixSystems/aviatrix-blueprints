# -----------------------------------------------------------------------------
# Pattern C: GKE Production Cluster — Variables
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

variable "kubernetes_version" {
  description = "GKE Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "vpc_self_link" {
  description = "VPC self-link for production"
  type        = string
}

variable "subnet_self_link" {
  description = "Subnet self-link for GKE nodes"
  type        = string
}

variable "pod_cidr" {
  description = "Pod CIDR for VPC-native clusters"
  type        = string
  default     = "100.64.0.0/16"
}

variable "master_ipv4_cidr_block" {
  description = "CIDR for GKE control plane (must be /28, unique per cluster)"
  type        = string
  default     = "172.16.0.0/28"
}

variable "node_machine_type" {
  description = "Machine type for default node pool"
  type        = string
  default     = "e2-standard-4"
}

variable "node_min_count" {
  type    = number
  default = 1
}

variable "node_max_count" {
  type    = number
  default = 10
}

variable "initial_node_count" {
  type    = number
  default = 3
}
