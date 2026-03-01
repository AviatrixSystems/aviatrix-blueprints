terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # kubernetes provider removed - no longer needed in Layer 2
    # ENIConfig creation moved to Layer 3 (node-group deployment)
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2"
    }
  }
}

# IAM role for reader access (example)
resource "aws_iam_role" "reader_role" {
  name = "${var.cluster_name}-reader-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = var.tags
}

# IAM role for service accounts - ALB Controller
module "iam_irsa_alb_controller" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.2"

  name                                   = "${var.cluster_name}-alb-controller-role"
  attach_load_balancer_controller_policy = true
  attach_vpc_cni_policy                  = true
  vpc_cni_enable_ipv4                    = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = var.tags
}

# IAM role for ExternalDNS
module "external_dns_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.2"

  name                       = "${var.cluster_name}-external-dns"
  attach_external_dns_policy = true

  # Restrict to specific hosted zone if provided, otherwise allow all
  external_dns_hosted_zone_arns = var.route53_zone_id != "" ? [
    "arn:aws:route53:::hostedzone/${var.route53_zone_id}"
  ] : ["arn:aws:route53:::hostedzone/*"]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }

  tags = var.tags
}

# Security group for cluster-level traffic (e.g., monitoring)
resource "aws_security_group" "cluster_additional" {
  name        = "${var.cluster_name}-cluster-additional-sg"
  description = "Additional security group for ${var.cluster_name} cluster"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow monitoring traffic"
    from_port   = 8080
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cluster-additional-sg"
  })
}

# Security group for pods (used by ENIConfig)
resource "aws_security_group" "pod" {
  name        = "${var.cluster_name}-pod-sg"
  description = "Security group for ${var.cluster_name} pods"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-pod-sg"
  })
}

# Allow nodes to communicate with pods
resource "aws_vpc_security_group_ingress_rule" "pod_from_nodes" {
  security_group_id = aws_security_group.pod.id
  description       = "Allow all traffic from node security group"

  referenced_security_group_id = module.eks.node_security_group_id
  ip_protocol                  = "-1"
}

# Allow pods to communicate with each other
resource "aws_vpc_security_group_ingress_rule" "pod_from_pods" {
  security_group_id = aws_security_group.pod.id
  description       = "Allow all traffic from other pods"

  referenced_security_group_id = aws_security_group.pod.id
  ip_protocol                  = "-1"
}

# Allow pods to communicate with the cluster control plane (for API server access)
resource "aws_vpc_security_group_ingress_rule" "cluster_from_pods" {
  security_group_id = module.eks.cluster_primary_security_group_id
  description       = "Allow pods to reach EKS control plane"

  referenced_security_group_id = aws_security_group.pod.id
  ip_protocol                  = "-1"
}

# Allow EKS control plane to reach pod webhooks (e.g., AWS LB Controller, cert-manager)
resource "aws_vpc_security_group_ingress_rule" "pods_from_cluster" {
  security_group_id = aws_security_group.pod.id
  description       = "Allow EKS control plane to reach pod webhooks"

  referenced_security_group_id = module.eks.cluster_primary_security_group_id
  from_port                    = 9443
  to_port                      = 9443
  ip_protocol                  = "tcp"
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.9"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  endpoint_public_access = true

  # Cluster addons
  # NOTE: CoreDNS is deployed in Layer 3 (node-group) to avoid waiting for nodes during cluster deployment
  addons = {
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
          # Enable custom networking - pods use secondary CIDR (100.64.x.x) via ENIConfig
          AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
          # Match ENIConfig resources by node's AZ label
          ENI_CONFIG_LABEL_DEF = "topology.kubernetes.io/zone"
          # CRITICAL: Disable CNI SNAT so Aviatrix can handle it
          AWS_VPC_K8S_CNI_EXTERNALSNAT = "true"
        }
      })
    }
  }

  vpc_id                        = var.vpc_id
  subnet_ids                    = var.subnet_ids
  control_plane_subnet_ids      = var.subnet_ids
  additional_security_group_ids = [aws_security_group.cluster_additional.id]

  # Node groups are managed separately in eks-node-group module
  # This solves the chicken-and-egg problem where node group count/for_each
  # depends on cluster outputs that don't exist during initial plan
  eks_managed_node_groups = {}

  # Cluster access entry - enable cluster creator as admin
  enable_cluster_creator_admin_permissions = true

  # Additional access entries
  access_entries = {
    reader = {
      kubernetes_groups = []
      principal_arn     = aws_iam_role.reader_role.arn

      policy_associations = {
        view = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = var.tags
}


#####################
# Aviatrix Controller Onboarding
#####################
# Register the EKS cluster with Aviatrix Controller for Smart Groups
# This allows the controller to build workload-based security policies

resource "aviatrix_kubernetes_cluster" "this" {
  count = var.enable_aviatrix_onboarding ? 1 : 0

  cluster_id          = module.eks.cluster_arn
  use_csp_credentials = true

  depends_on = [module.eks]
}

# EKS access entry for Aviatrix Controller IAM role
# This allows the Aviatrix Controller to authenticate to the EKS cluster
resource "aws_eks_access_entry" "aviatrix_controller" {
  count = var.enable_aviatrix_onboarding && var.aviatrix_controller_role_arn != "" ? 1 : 0

  cluster_name      = module.eks.cluster_name
  principal_arn     = var.aviatrix_controller_role_arn
  kubernetes_groups = ["view-nodes"]
  type              = "STANDARD"

  depends_on = [module.eks]
}

# Associate AmazonEKSViewPolicy with Aviatrix Controller access entry
# This provides read access to most Kubernetes resources
resource "aws_eks_access_policy_association" "aviatrix_controller" {
  count = var.enable_aviatrix_onboarding && var.aviatrix_controller_role_arn != "" ? 1 : 0

  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  principal_arn = var.aviatrix_controller_role_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.aviatrix_controller]
}

# ClusterRole for viewing nodes (required by Aviatrix for Smart Groups)
# AmazonEKSViewPolicy doesn't include nodes, so we need this additional role
resource "kubernetes_cluster_role" "view_nodes" {
  count = var.enable_aviatrix_onboarding && var.aviatrix_controller_role_arn != "" ? 1 : 0

  metadata {
    name = "view-nodes"
  }

  rule {
    verbs      = ["get", "list", "watch"]
    api_groups = [""]
    resources  = ["nodes"]
  }

  depends_on = [module.eks]
}

# ClusterRoleBinding to grant view-nodes group the view-nodes ClusterRole
resource "kubernetes_cluster_role_binding" "view_nodes" {
  count = var.enable_aviatrix_onboarding && var.aviatrix_controller_role_arn != "" ? 1 : 0

  metadata {
    name = "view-nodes"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.view_nodes[0].metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = "view-nodes"
    api_group = "rbac.authorization.k8s.io"
  }

  depends_on = [kubernetes_cluster_role.view_nodes]
}
