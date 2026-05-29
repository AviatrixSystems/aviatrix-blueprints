# ─────────────────────────────────────────────────────────────────────────────
# Architecture Recommendations — Opt-in Toggles (Shared Cluster / AKS)
# Inline Helm charts — Azure equivalents of modules/recommendations (AWS-only).
# All toggles default to false; enable in terraform.tfvars to activate.
# ─────────────────────────────────────────────────────────────────────────────

resource "helm_release" "calico" {
  count            = var.enable_network_policy ? 1 : 0
  name             = "tigera-operator"
  repository       = "https://docs.tigera.io/calico/charts"
  chart            = "tigera-operator"
  namespace        = "tigera-operator"
  create_namespace = true

  depends_on = [azurerm_kubernetes_cluster_node_pool.shared]
}

resource "helm_release" "gatekeeper" {
  count            = var.enable_gatekeeper ? 1 : 0
  name             = "gatekeeper"
  repository       = "https://open-policy-agent.github.io/gatekeeper/charts"
  chart            = "gatekeeper"
  namespace        = "gatekeeper-system"
  create_namespace = true

  depends_on = [azurerm_kubernetes_cluster_node_pool.shared]
}

resource "helm_release" "external_secrets" {
  count            = var.enable_external_secrets ? 1 : 0
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  depends_on = [azurerm_kubernetes_cluster_node_pool.shared]
}

resource "helm_release" "falco" {
  count            = var.enable_falco ? 1 : 0
  name             = "falco"
  repository       = "https://falcosecurity.github.io/charts"
  chart            = "falco"
  namespace        = "falco"
  create_namespace = true

  depends_on = [azurerm_kubernetes_cluster_node_pool.shared]
}

resource "helm_release" "prometheus_stack" {
  count            = var.enable_prometheus_stack ? 1 : 0
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true

  depends_on = [azurerm_kubernetes_cluster_node_pool.shared]
}

resource "helm_release" "fluent_bit" {
  count      = var.enable_fluent_bit ? 1 : 0
  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  namespace  = "kube-system"

  set {
    name  = "config.outputs"
    value = "[OUTPUT]\n    Name  azure\n    Match *\n"
  }

  depends_on = [azurerm_kubernetes_cluster_node_pool.shared]
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
    value = "azure"
  }

  depends_on = [azurerm_kubernetes_cluster_node_pool.shared]
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
  description = "Install External Secrets Operator (Azure Key Vault → K8s Secrets)"
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
  description = "Install Fluent Bit for log aggregation to Azure Monitor Logs"
  type        = bool
  default     = false
}

variable "enable_node_termination_handler" {
  # AKS manages Spot eviction natively via VMSS — no external handler required.
  description = "No-op on AKS — Spot node lifecycle is managed natively by Azure VMSS"
  type        = bool
  default     = false
}

variable "enable_cluster_autoscaler" {
  # AKS built-in autoscaler is enabled at node pool level (auto_scaling_enabled = true).
  description = "No-op on AKS — cluster autoscaling is configured at the node pool level"
  type        = bool
  default     = false
}

variable "enable_velero" {
  description = "Install Velero for cluster backup to Azure Blob Storage"
  type        = bool
  default     = false
}
