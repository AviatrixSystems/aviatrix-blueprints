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
