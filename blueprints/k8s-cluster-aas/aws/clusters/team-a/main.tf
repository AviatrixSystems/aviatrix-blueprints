#####################
# EKS Cluster Layer (Layer 2) - Team-A
#
# Provisions the EKS control plane using outputs from the network layer.
# Node groups are managed separately in Layer 3 (nodes/).
#
# Each team is cluster-admin in their own cluster (Pattern A isolation).
#
# Authentication:
#   - Aviatrix: AVIATRIX_CONTROLLER_IP, AVIATRIX_USERNAME, AVIATRIX_PASSWORD env vars
#   - AWS: AWS_PROFILE or AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY
#####################

provider "aws" {
  region = data.terraform_remote_state.network.outputs.aws_region
}

provider "aviatrix" {
  controller_ip           = var.controller_ip
  username                = var.controller_username
  password                = var.controller_password
  skip_version_validation = true
}

#####################
# Team-A EKS Cluster
# Module source: terraform-aws-modules/eks/aws (registry)
#####################

module "team_a_eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = data.terraform_remote_state.network.outputs.team_a_cluster_name
  cluster_version = var.kubernetes_version

  # Network configuration from Layer 1
  vpc_id     = data.terraform_remote_state.network.outputs.team_a_vpc_id
  subnet_ids = data.terraform_remote_state.network.outputs.team_a_private_subnet_ids

  # API server endpoint access — toggle via enable_private_endpoint
  cluster_endpoint_public_access  = var.enable_private_endpoint ? false : true
  cluster_endpoint_private_access = true

  # Control plane logging — toggle via enable_control_plane_logging
  cluster_enabled_log_types = var.enable_control_plane_logging ? [
    "audit", "api", "authenticator", "controllerManager", "scheduler"
  ] : []

  # Enable IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # EKS managed addons
  cluster_addons = {
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        # Enable custom networking for pod CIDR (100.64.0.0/16)
        env = {
          AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
          ENI_CONFIG_LABEL_DEF               = "topology.kubernetes.io/zone"
        }
      })
    }
  }

  # Cluster access
  enable_cluster_creator_admin_permissions = true

  # Grant Aviatrix controller read access for K8s inventory (namespaces, pods, DCF CRDs)
  access_entries = {
    aviatrix_controller = {
      kubernetes_groups = ["avx-controller"]
      principal_arn     = data.aviatrix_account.aws_account.aws_role_arn

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

  tags = {
    Environment = "demo"
    Team        = "team-a"
    Terraform   = "true"
    Pattern     = "cluster-aas"
  }
}

#####################
# IRSA - ALB Controller
#####################

module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${data.terraform_remote_state.network.outputs.team_a_cluster_name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.team_a_eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = {
    Environment = "demo"
    Team        = "team-a"
    Terraform   = "true"
  }
}

#####################
# IRSA - ExternalDNS
#####################

module "external_dns_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                     = "${data.terraform_remote_state.network.outputs.team_a_cluster_name}-external-dns"
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = ["arn:aws:route53:::hostedzone/${data.terraform_remote_state.network.outputs.route53_zone_id}"]

  oidc_providers = {
    main = {
      provider_arn               = module.team_a_eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }

  tags = {
    Environment = "demo"
    Team        = "team-a"
    Terraform   = "true"
  }
}

