#####################
# EKS Cluster
#####################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.9"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version

  endpoint_public_access = true

  addons = {
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
          # Disable CNI SNAT - Aviatrix spoke gateway handles SNAT
          AWS_VPC_K8S_CNI_EXTERNALSNAT = "true"
        }
      })
    }
    coredns = {
      most_recent = true
    }
  }

  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.eks_private[*].id

  # No inline node groups - managed separately for dependency control
  eks_managed_node_groups = {}

  enable_cluster_creator_admin_permissions = true

  tags = {
    Terraform   = "true"
    Environment = "demo"
  }
}

#####################
# EKS Managed Node Group
#####################

resource "aws_eks_node_group" "default" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "${var.name_prefix}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.eks_private[*].id

  instance_types = var.node_group_config.instance_types
  capacity_type  = var.node_group_config.capacity_type

  scaling_config {
    min_size     = var.node_group_config.min_size
    max_size     = var.node_group_config.max_size
    desired_size = var.node_group_config.desired_size
  }

  tags = {
    Terraform   = "true"
    Environment = "demo"
  }

  # Nodes need the spoke gateway for internet access (image pulls)
  depends_on = [
    module.spoke,
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
  ]
}

#####################
# Node IAM Role
#####################

resource "aws_iam_role" "node" {
  name = "${var.name_prefix}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Terraform = "true"
  }
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

#####################
# IRSA - ALB Controller
#####################

module "iam_irsa_alb_controller" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.2"

  name                                   = "${local.cluster_name}-alb-controller-role"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = {
    Terraform = "true"
  }
}

#####################
# IRSA - LiteLLM (Bedrock Access)
#####################

module "iam_irsa_litellm" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.2"

  name = "${local.cluster_name}-litellm-bedrock-role"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["default:litellm"]
    }
  }

  tags = {
    Terraform = "true"
  }
}

resource "aws_iam_role_policy" "litellm_bedrock" {
  name = "${local.cluster_name}-litellm-bedrock"
  role = module.iam_irsa_litellm.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:*:*:inference-profile/*"
        ]
      }
    ]
  })
}
