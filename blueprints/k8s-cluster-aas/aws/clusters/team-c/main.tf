#####################
# EKS Cluster Layer (Layer 2) - Team-C
#
# Provisions the EKS control plane using outputs from the network layer.
# Node groups are managed separately in Layer 3 (nodes/).
#####################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2.0"
    }
  }
}

provider "aws" {
  region = data.terraform_remote_state.network.outputs.aws_region
}

provider "aviatrix" {
  skip_version_validation = true
}

#####################
# Team-C EKS Cluster
#####################

module "team_c_eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = data.terraform_remote_state.network.outputs.team_c_cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = data.terraform_remote_state.network.outputs.team_c_vpc_id
  subnet_ids = data.terraform_remote_state.network.outputs.team_c_private_subnet_ids

  # API server endpoint access — toggle via enable_private_endpoint
  cluster_endpoint_public_access  = var.enable_private_endpoint ? false : true
  cluster_endpoint_private_access = true

  # Control plane logging — toggle via enable_control_plane_logging
  cluster_enabled_log_types = var.enable_control_plane_logging ? [
    "audit", "api", "authenticator", "controllerManager", "scheduler"
  ] : []

  enable_irsa = true

  cluster_addons = {
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
          AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
          ENI_CONFIG_LABEL_DEF               = "topology.kubernetes.io/zone"
        }
      })
    }
  }

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
    Team        = "team-c"
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

  role_name                              = "${data.terraform_remote_state.network.outputs.team_c_cluster_name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.team_c_eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = {
    Environment = "demo"
    Team        = "team-c"
    Terraform   = "true"
  }
}

#####################
# IRSA - ExternalDNS
#####################

module "external_dns_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                     = "${data.terraform_remote_state.network.outputs.team_c_cluster_name}-external-dns"
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = ["arn:aws:route53:::hostedzone/${data.terraform_remote_state.network.outputs.route53_zone_id}"]

  oidc_providers = {
    main = {
      provider_arn               = module.team_c_eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }

  tags = {
    Environment = "demo"
    Team        = "team-c"
    Terraform   = "true"
  }
}

#####################
# Outputs
#####################

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.team_c_eks.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.team_c_eks.cluster_arn
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.team_c_eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded CA certificate"
  value       = module.team_c_eks.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.team_c_eks.oidc_provider_arn
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for ALB Controller"
  value       = module.alb_controller_irsa.iam_role_arn
}

output "external_dns_role_arn" {
  description = "IAM role ARN for ExternalDNS"
  value       = module.external_dns_irsa.iam_role_arn
}
