# ─────────────────────────────────────────────────────────────────────────────
# Architecture Recommendations — Opt-in Toggles (Production / GKE)
# Inline Helm charts — GCP equivalents of modules/recommendations (AWS-only).
# All toggles default to false; enable in terraform.tfvars to activate.
# ─────────────────────────────────────────────────────────────────────────────

resource "helm_release" "calico" {
  count            = var.enable_network_policy ? 1 : 0
  name             = "tigera-operator"
  repository       = "https://docs.tigera.io/calico/charts"
  chart            = "tigera-operator"
  namespace        = "tigera-operator"
  create_namespace = true

  depends_on = [google_container_node_pool.prod_default]
}

resource "helm_release" "gatekeeper" {
  count            = var.enable_gatekeeper ? 1 : 0
  name             = "gatekeeper"
  repository       = "https://open-policy-agent.github.io/gatekeeper/charts"
  chart            = "gatekeeper"
  namespace        = "gatekeeper-system"
  create_namespace = true

  depends_on = [google_container_node_pool.prod_default]
}

resource "helm_release" "external_secrets" {
  count            = var.enable_external_secrets ? 1 : 0
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  depends_on = [google_container_node_pool.prod_default]
}

resource "helm_release" "falco" {
  count            = var.enable_falco ? 1 : 0
  name             = "falco"
  repository       = "https://falcosecurity.github.io/charts"
  chart            = "falco"
  namespace        = "falco"
  create_namespace = true

  depends_on = [google_container_node_pool.prod_default]
}

resource "helm_release" "prometheus_stack" {
  count            = var.enable_prometheus_stack ? 1 : 0
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true

  depends_on = [google_container_node_pool.prod_default]
}

resource "helm_release" "fluent_bit" {
  count      = var.enable_fluent_bit ? 1 : 0
  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  namespace  = "kube-system"

  set {
    name  = "config.outputs"
    value = "[OUTPUT]\n    Name  stackdriver\n    Match *\n"
  }

  depends_on = [google_container_node_pool.prod_default]
}

resource "helm_release" "velero" {
  count            = var.enable_velero ? 1 : 0
  name             = "velero"
  repository       = "https://vmware-tanzu.github.io/helm-charts"
  chart            = "velero"
  namespace        = "velero"
  create_namespace = true

  set {
    name  = "provider"
    value = "gcp"
  }

  depends_on = [google_container_node_pool.prod_default]
}

variable "enable_network_policy" {
  description = "Install Calico via tigera-operator for in-cluster NetworkPolicy enforcement (defense-in-depth)"
  type        = bool
  default     = false
}

variable "enable_gatekeeper" {
  description = "Install OPA Gatekeeper for admission policy-as-code"
  type        = bool
  default     = false
}

variable "enable_external_secrets" {
  description = "Install External Secrets Operator (GCP Secret Manager → K8s Secrets)"
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
  description = "Install Fluent Bit for log aggregation to Google Cloud Logging"
  type        = bool
  default     = false
}

variable "enable_node_termination_handler" {
  # GKE manages Spot (Preemptible) eviction natively — no external handler required.
  description = "No-op on GKE — Spot node lifecycle is managed natively by GKE"
  type        = bool
  default     = false
}

variable "enable_cluster_autoscaler" {
  # GKE built-in cluster autoscaler is configured at the node pool level.
  description = "No-op on GKE — cluster autoscaling is configured at the node pool level"
  type        = bool
  default     = false
}

variable "enable_velero" {
  description = "Install Velero for cluster backup to Google Cloud Storage"
  type        = bool
  default     = false
}
