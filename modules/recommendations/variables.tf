# ─────────────────────────────────────────────────────────────────────────────
# Recommendations Module — Variables
#
# All toggles default to false (opt-in). Set to true to enable each
# recommendation from the architecture analysis.
#
# Reference: /ARCHITECTURE-ANALYSIS.md
# ─────────────────────────────────────────────────────────────────────────────

# ──── Required Inputs ────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "EKS cluster name (used for IRSA role naming and Helm values)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN for IRSA roles"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ──── Security Toggles ──────────────────────────────────────────────────────

variable "enable_network_policy" {
  description = <<-EOT
    Install Calico for Kubernetes NetworkPolicy enforcement.
    Adds defense-in-depth alongside Aviatrix DCF.
    Ref: https://github.com/ahmetb/kubernetes-network-policy-recipes
  EOT
  type        = bool
  default     = false
}

variable "enable_gatekeeper" {
  description = <<-EOT
    Install OPA Gatekeeper for policy-as-code (image allowlists, resource limits, label enforcement).
    Ref: https://open-policy-agent.github.io/gatekeeper/
  EOT
  type        = bool
  default     = false
}

variable "enable_external_secrets" {
  description = <<-EOT
    Install External Secrets Operator to sync secrets from AWS Secrets Manager / SSM into K8s.
    Ref: https://external-secrets.io/
  EOT
  type        = bool
  default     = false
}

variable "enable_falco" {
  description = <<-EOT
    Install Falco for runtime threat detection (syscall monitoring, container drift).
    Ref: https://falco.org/
  EOT
  type        = bool
  default     = false
}

# ──── Observability Toggles ─────────────────────────────────────────────────

variable "enable_prometheus_stack" {
  description = <<-EOT
    Install kube-prometheus-stack (Prometheus + Grafana + alerting rules).
    Ref: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
  EOT
  type        = bool
  default     = false
}

variable "enable_fluent_bit" {
  description = <<-EOT
    Install Fluent Bit for log aggregation to CloudWatch Logs.
    Ref: https://docs.fluentbit.io/manual/
  EOT
  type        = bool
  default     = false
}

# ──── Resilience Toggles ────────────────────────────────────────────────────

variable "enable_node_termination_handler" {
  description = <<-EOT
    Install AWS Node Termination Handler for graceful SPOT instance draining.
    Recommended when capacity_type = SPOT.
    Ref: https://github.com/aws/aws-node-termination-handler
  EOT
  type        = bool
  default     = false
}

variable "enable_cluster_autoscaler" {
  description = <<-EOT
    Install Cluster Autoscaler for dynamic node scaling.
    Ref: https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler
  EOT
  type        = bool
  default     = false
}

variable "enable_velero" {
  description = <<-EOT
    Install Velero for cluster backup and disaster recovery (backs up to S3).
    Ref: https://velero.io/
  EOT
  type        = bool
  default     = false
}

# ──── Chart Versions ────────────────────────────────────────────────────────

variable "calico_chart_version" {
  description = "Tigera Calico operator Helm chart version"
  type        = string
  default     = "3.28.0"
}

variable "gatekeeper_chart_version" {
  description = "OPA Gatekeeper Helm chart version"
  type        = string
  default     = "3.16.0"
}

variable "external_secrets_chart_version" {
  description = "External Secrets Operator Helm chart version"
  type        = string
  default     = "0.9.0"
}

variable "falco_chart_version" {
  description = "Falco Helm chart version"
  type        = string
  default     = "4.4.0"
}

variable "prometheus_stack_chart_version" {
  description = "kube-prometheus-stack Helm chart version"
  type        = string
  default     = "61.0.0"
}

variable "fluent_bit_chart_version" {
  description = "Fluent Bit Helm chart version"
  type        = string
  default     = "0.47.0"
}

variable "nth_chart_version" {
  description = "AWS Node Termination Handler Helm chart version"
  type        = string
  default     = "0.22.0"
}

variable "cluster_autoscaler_chart_version" {
  description = "Cluster Autoscaler Helm chart version"
  type        = string
  default     = "9.37.0"
}

variable "velero_chart_version" {
  description = "Velero Helm chart version"
  type        = string
  default     = "7.0.0"
}
