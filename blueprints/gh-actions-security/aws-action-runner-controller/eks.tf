# IAM role for the EKS cluster control plane.
resource "aws_iam_role" "eks_cluster" {
  name = "${local.name_prefix}-eks-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# IAM role for EKS managed node group.
resource "aws_iam_role" "eks_nodes" {
  name = "${local.name_prefix}-eks-nodes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# EKS cluster. Runs in private subnets; all node/pod egress via Aviatrix spoke GW.
# EKS uses the VPC CNI plugin — each pod gets a real VPC IP, which is required
# for DCF k8s SmartGroup matching (pod IPs must be preserved, not SNATted).
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "eks-${local.name_prefix}"
  cluster_version = var.eks_kubernetes_version

  vpc_id                   = aws_vpc.this.id
  subnet_ids               = [aws_subnet.eks_primary.id, aws_subnet.eks_secondary.id]
  control_plane_subnet_ids = [aws_subnet.eks_primary.id, aws_subnet.eks_secondary.id]

  # Public endpoint for kubectl (API server is AWS-managed; only worker data-plane
  # traffic goes through the spoke). Set to false and add a bastion for stricter posture.
  cluster_endpoint_public_access = true

  # enable_cluster_creator_admin_permissions binds the API-key caller at apply
  # time — kept as a safety net in case access_entries resolution fails.
  enable_cluster_creator_admin_permissions = true

  # access_entries = deployer role (auto-detected) + any extra ARNs from tfvars.
  # data.aws_iam_session_context.deployer.issuer_arn resolves the source IAM
  # role for assumed-role sessions (SSO, CI), so kubectl access is granted to
  # the human's role — not just the transient session ARN.
  access_entries = {
    for arn in toset(concat(
      [data.aws_iam_session_context.deployer.issuer_arn],
      var.cluster_admin_arns,
      )) : replace(arn, "/", "_") => {
      principal_arn     = arn
      type              = "STANDARD"
      kubernetes_groups = []
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  iam_role_arn = aws_iam_role.eks_cluster.arn

  eks_managed_node_groups = {
    default = {
      name                     = "nodes"
      instance_types           = [var.eks_node_instance_type]
      min_size                 = var.eks_node_count
      max_size                 = var.eks_node_count + 2
      desired_size             = var.eks_node_count
      iam_role_use_name_prefix = false

      subnet_ids   = [aws_subnet.eks_primary.id]
      iam_role_arn = aws_iam_role.eks_nodes.arn

      labels = local.common_tags
    }
  }

  tags = local.common_tags

  # EKS nodes need to reach ECR, S3, and the EKS endpoint — all via the spoke GW
  # once single_ip_snat programs the private RT. Ensure spoke GW is up first.
  depends_on = [
    aviatrix_spoke_gateway.this,
    aws_route_table_association.eks_primary,
    aws_route_table_association.eks_secondary,
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_readonly,
  ]
}

# Disable source/destination check on EKS node ENIs is not needed — VPC CNI
# handles pod IP routing at the hypervisor level. No extra ENI config required.

# Disable pod SNAT so pod IPs reach the spoke GW unmasked (required for
# DCF k8s SmartGroup matching). The aws-node DaemonSet reads AWS_VPC_K8S_CNI_EXTERNALSNAT
# from its own env spec (not the ConfigMap), so we patch the DaemonSet directly.
# Aviatrix spoke GW then SNATs to the gateway EIP.
resource "kubernetes_env" "aws_node_externalsnat" {
  api_version = "apps/v1"
  kind        = "DaemonSet"

  metadata {
    name      = "aws-node"
    namespace = "kube-system"
  }

  container = "aws-node"

  env {
    name  = "AWS_VPC_K8S_CNI_EXTERNALSNAT"
    value = "true"
  }

  force      = true
  depends_on = [module.eks]
}

# Onboard EKS cluster to Aviatrix controller using CSP credentials.
# Requires: k8s feature enabled on controller (see Prerequisites in CLAUDE.md).
resource "aviatrix_kubernetes_cluster" "this" {
  cluster_id          = lower(module.eks.cluster_arn)
  use_csp_credentials = true

  depends_on = [module.eks]
}
