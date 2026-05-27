# =============================================================================
# Aviatrix DCF CRDs
# =============================================================================

# k8s-firewall Helm chart: installs FirewallPolicy and WebgroupPolicy CRDs
# (networking.aviatrix.com/v1alpha1) plus a ClusterRole for the controller.
# No pods are deployed. The aviatrix-network-policy-controller (NPC) crashes
# on startup with "no matches for kind FirewallPolicy" if these CRDs are absent.
# Source: https://github.com/AviatrixSystems/k8s-firewall-charts
resource "helm_release" "aviatrix_crds" {
  name             = "aviatrix-crds"
  repository       = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart            = "k8s-firewall"
  version          = "9.0.0"
  namespace        = "kube-system"
  create_namespace = false

  depends_on = [module.eks]
}

# =============================================================================
# Storage
# =============================================================================

# gp3 StorageClass using the EBS CSI driver (aws-ebs-csi-driver addon).
# EKS 1.26+ requires the CSI driver for PVC provisioning; the in-tree
# kubernetes.io/aws-ebs provisioner is deprecated and cannot provision volumes.
# Setting as cluster default so the Obot Helm chart's PVC (no storageClassName)
# binds automatically. gp3 is preferred over gp2: 20% lower cost, higher IOPS.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
  depends_on = [module.eks]
}

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
