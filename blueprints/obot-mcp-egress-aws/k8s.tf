# =============================================================================
# Kubernetes Namespaces
# =============================================================================

# obot-system: owns Obot pods and aviatrix-network-policy-controller
resource "kubernetes_namespace_v1" "obot_system" {
  metadata {
    name   = var.obot_namespace
    labels = { app = "obot", role = "platform" }
  }
  depends_on = [module.eks]
}

# obot-mcp: owns all Obot-managed MCP server pods.
# Helm adoption labels set here before helm install to prevent namespace conflict.
resource "kubernetes_namespace_v1" "obot_mcp" {
  metadata {
    name = var.obot_mcp_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "Helm"
    }
    annotations = {
      "meta.helm.sh/release-name"      = "obot"
      "meta.helm.sh/release-namespace" = var.obot_namespace
    }
  }
  depends_on = [module.eks]
}
