variable "aviatrix_aws_account_name" {
  description = "Aviatrix access account name for AWS (used to grant controller EKS access)"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the shared EKS cluster"
  type        = string
  default     = "1.35"
}

variable "cluster_endpoint_public_access" {
  description = "Whether to enable public access to the EKS API endpoint"
  type        = bool
  default     = true
}

# ──── Architecture Recommendation Toggles ────────────────────────────────────

variable "enable_private_endpoint" {
  description = <<-EOT
    Disable public access to the EKS API server endpoint (private-only).
    Overrides cluster_endpoint_public_access when true.
    Ref: https://docs.aws.amazon.com/eks/latest/userguide/private-clusters.html
  EOT
  type        = bool
  default     = false
}

variable "enable_control_plane_logging" {
  description = <<-EOT
    Enable EKS control plane logging (audit, api, authenticator, controllerManager, scheduler).
    Ref: https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html
  EOT
  type        = bool
  default     = false
}
