# ─────────────────────────────────────────────────────────────────────────────
# Architecture Recommendations — Opt-in Toggles (Team-B)
# See /ARCHITECTURE-ANALYSIS.md | Module: /blueprints/modules/recommendations/
# ─────────────────────────────────────────────────────────────────────────────

module "recommendations" {
  source = "../../../../../modules/recommendations"

  cluster_name      = data.terraform_remote_state.cluster.outputs.cluster_name
  oidc_provider_arn = data.terraform_remote_state.cluster.outputs.oidc_provider_arn
  aws_region        = data.terraform_remote_state.network.outputs.aws_region

  tags = {
    Environment = "demo"
    Team        = "team-b"
    Pattern     = "cluster-aas"
    Terraform   = "true"
  }

  enable_network_policy           = var.enable_network_policy
  enable_gatekeeper               = var.enable_gatekeeper
  enable_external_secrets         = var.enable_external_secrets
  enable_falco                    = var.enable_falco
  enable_prometheus_stack         = var.enable_prometheus_stack
  enable_fluent_bit               = var.enable_fluent_bit
  enable_node_termination_handler = var.enable_node_termination_handler
  enable_cluster_autoscaler       = var.enable_cluster_autoscaler
  enable_velero                   = var.enable_velero
}

variable "enable_network_policy" {
  description = "Install Calico for in-cluster NetworkPolicy enforcement (defense-in-depth)"
  type        = bool
  default     = true
}

variable "enable_gatekeeper" {
  description = "Install OPA Gatekeeper for admission policy-as-code"
  type        = bool
  default     = false
}

variable "enable_external_secrets" {
  description = "Install External Secrets Operator (AWS Secrets Manager → K8s Secrets)"
  type        = bool
  default     = false
}

variable "enable_falco" {
  description = "Install Falco for runtime threat detection"
  type        = bool
  default     = false
}

variable "enable_prometheus_stack" {
  description = "Install kube-prometheus-stack (Prometheus + Grafana + alerts)"
  type        = bool
  default     = false
}

variable "enable_fluent_bit" {
  description = "Install Fluent Bit for log aggregation to CloudWatch"
  type        = bool
  default     = false
}

variable "enable_node_termination_handler" {
  description = "Install AWS Node Termination Handler (recommended for SPOT)"
  type        = bool
  default     = false
}

variable "enable_cluster_autoscaler" {
  description = "Install Cluster Autoscaler for dynamic node scaling"
  type        = bool
  default     = false
}

variable "enable_velero" {
  description = "Install Velero for cluster backup to S3"
  type        = bool
  default     = false
}
