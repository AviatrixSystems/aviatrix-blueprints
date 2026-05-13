# =============================================================================
# EKS Cluster
# =============================================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${local.name}-cluster"
  cluster_version = var.cluster_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }
    # aws-ebs-csi-driver is declared as a separate aws_eks_addon resource below
    # because its IRSA role ARN depends on module.eks outputs (oidc_provider_arn,
    # cluster_oidc_issuer_url). Inlining it here would create a circular dependency:
    # module.eks needs the IRSA ARN, but the IRSA role needs module.eks outputs.
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    system = {
      instance_types = [var.node_instance_type]
      min_size       = 0
      max_size       = var.node_max_size
      # Start at 0; scale to desired after Aviatrix spoke GW programs routes.
      # Nodes started before routes are in place may fail to reach ECR/S3 endpoints.
      desired_size = var.node_desired_size
      labels       = { role = "system" }
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = "${local.name}-cluster"
  }

  tags = local.tags
}

# Aviatrix app role access entry: CoPilot uses aviatrix-role-app to authenticate
# to the EKS API for DCF Kubernetes enforcement onboarding. Without this entry,
# onboarding fails with "Fail" status in CoPilot > Security > DCF > Kubernetes Clusters.
# Policy: AmazonEKSClusterAdminPolicy (required for agent deploy — see association resource).
# RBAC: view-nodes group grants node enumeration beyond the EKS managed policy scope.
resource "aws_eks_access_entry" "aviatrix_controller" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = var.aviatrix_app_role_arn
  kubernetes_groups = ["view-nodes"]
  type              = "STANDARD"

  depends_on = [module.eks]
}

resource "aws_eks_access_policy_association" "aviatrix_controller" {
  cluster_name  = module.eks.cluster_name
  principal_arn = var.aviatrix_app_role_arn
  # ClusterAdmin required: CoPilot deploys the aviatrix-system agent (DaemonSet +
  # CRD installation) after onboarding. ViewPolicy allows cluster listing but not
  # namespace/DaemonSet creation. Without ClusterAdmin the agent never deploys,
  # FirewallPolicy CRD is never installed, and NPC crashes on startup.
  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.aviatrix_controller]
}

resource "kubernetes_cluster_role" "aviatrix_view_nodes" {
  metadata {
    name = "view-nodes"
  }

  rule {
    verbs      = ["get", "list", "watch"]
    api_groups = [""]
    resources  = ["nodes"]
  }
}

resource "kubernetes_cluster_role_binding" "aviatrix_view_nodes" {
  metadata {
    name = "view-nodes"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.aviatrix_view_nodes.metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = "view-nodes"
    api_group = "rbac.authorization.k8s.io"
  }

  depends_on = [aws_eks_access_entry.aviatrix_controller]
}

# CoPilot also needs to list Aviatrix CRDs (FirewallPolicy, WebgroupPolicy) to
# display DCF enforcement state. AmazonEKSViewPolicy covers core resources only;
# custom API groups require a dedicated ClusterRole.
resource "kubernetes_cluster_role" "aviatrix_crd_view" {
  metadata {
    name = "aviatrix-crd-view"
  }

  rule {
    verbs      = ["get", "list", "watch"]
    api_groups = ["networking.aviatrix.com"]
    resources  = ["firewallpolicies", "webgrouppolicies"]
  }
}

resource "kubernetes_cluster_role_binding" "aviatrix_crd_view" {
  metadata {
    name = "aviatrix-crd-view"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.aviatrix_crd_view.metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = "view-nodes"
    api_group = "rbac.authorization.k8s.io"
  }

  depends_on = [aws_eks_access_entry.aviatrix_controller]
}

# vpc-cni addon: EXTERNALSNAT preserves pod source IPs at the Aviatrix gateway.
# Without this, vpc-cni SNATs pod IPs to node IPs before traffic reaches the
# spoke gateway. SmartGroups resolve to pod IPs, so node IPs would never match
# FirewallPolicy CRD rules.
# AKS equivalent: ip-masq-agent nonMasqueradeCIDRs: 0.0.0.0/0
resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "vpc-cni"
  service_account_role_arn = aws_iam_role.vpc_cni_irsa.arn

  configuration_values = jsonencode({
    env = {
      AWS_VPC_K8S_CNI_EXTERNALSNAT = "true"
    }
  })

  depends_on = [module.eks]
}

# aws-ebs-csi-driver addon: required for PVC provisioning on EKS 1.26+.
# The in-tree kubernetes.io/aws-ebs provisioner is deprecated; gp3 StorageClass
# (k8s.tf) requires this addon. Declared outside cluster_addons to avoid a
# circular dependency (the IRSA role needs module.eks OIDC outputs).
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.ebs_csi_irsa.arn
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [module.eks]
}
