# -----------------------------------------------------------------------------
# Pattern C: EKS Non-Production Cluster
# Dedicated non-production cluster in isolated VPC
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

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
  region = var.aws_region
}

provider "aviatrix" {
  skip_version_validation = true
}

locals {
  cluster_name = "${data.terraform_remote_state.network.outputs.name_prefix}-nonprod"
}

module "eks_nonprod" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = data.terraform_remote_state.network.outputs.nonprod_vpc_id
  subnet_ids = data.terraform_remote_state.network.outputs.nonprod_private_subnets

  # API server endpoint access — toggle via enable_private_endpoint
  cluster_endpoint_public_access  = var.enable_private_endpoint ? false : true
  cluster_endpoint_private_access = true

  # Control plane logging — toggle via enable_control_plane_logging
  cluster_enabled_log_types = var.enable_control_plane_logging ? [
    "audit", "api", "authenticator", "controllerManager", "scheduler"
  ] : []

  cluster_addons = {
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
          AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
          AWS_VPC_K8S_CNI_EXTERNALSNAT       = "true"
          ENI_CONFIG_LABEL_DEF               = "topology.kubernetes.io/zone"
        }
      })
    }
    kube-proxy = {
      most_recent = true
    }
  }

  eks_managed_node_groups = {
    nonprod_workers = {
      name           = "${data.terraform_remote_state.network.outputs.name_prefix}-np-workers"
      instance_types = ["t3.large"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2

      labels = {
        environment = "non-production"
        cluster     = "nonprod"
      }
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
    Environment = "non-production"
    Pattern     = "C"
    ManagedBy   = "terraform"
  }
}
