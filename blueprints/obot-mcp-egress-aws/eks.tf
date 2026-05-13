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
