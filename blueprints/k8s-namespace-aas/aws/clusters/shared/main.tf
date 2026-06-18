#####################
# Pattern B: Namespace-as-a-Service — AWS Shared EKS Cluster (Layer 2)
#
# Provisions a single shared EKS cluster. All teams (team-a, team-b, team-c)
# get isolated namespaces within this cluster.
#
# Isolation is enforced by DCF SmartGroups (k8s_namespace type), NOT by RBAC alone.
# RBAC is NOT a hard security boundary — DCF is the primary network isolation.
#
# Authentication:
#   - Aviatrix: AVIATRIX_CONTROLLER_IP, AVIATRIX_USERNAME, AVIATRIX_PASSWORD env vars
#   - AWS: AWS_PROFILE or AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY env vars
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
# Shared EKS Cluster
#
# Uses terraform-aws-modules/eks/aws for the control plane.
# Node groups are managed separately in Layer 3 (nodes/).
#####################

module "shared_eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = data.terraform_remote_state.network.outputs.shared_cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = data.terraform_remote_state.network.outputs.shared_vpc_id
  subnet_ids = data.terraform_remote_state.network.outputs.shared_private_subnets

  # API server endpoint — enable_private_endpoint overrides cluster_endpoint_public_access
  cluster_endpoint_public_access  = var.enable_private_endpoint ? false : var.cluster_endpoint_public_access
  cluster_endpoint_private_access = true

  # Control plane logging — toggle via enable_control_plane_logging
  cluster_enabled_log_types = var.enable_control_plane_logging ? [
    "audit", "api", "authenticator", "controllerManager", "scheduler"
  ] : []

  # IRSA (IAM Roles for Service Accounts) — enabled by default in v20+
  # This is the AWS equivalent of Azure Workload Identity and GCP Workload Identity Federation

  # Cluster addons
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
    Environment = "prod"
    Pattern     = "namespace-aas"
    Terraform   = "true"
  }
}
