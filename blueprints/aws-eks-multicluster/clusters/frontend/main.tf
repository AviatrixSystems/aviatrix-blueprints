terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Aviatrix provider - uses environment variables for authentication:
# AVIATRIX_CONTROLLER_IP, AVIATRIX_USERNAME, AVIATRIX_PASSWORD
provider "aviatrix" {
  skip_version_validation = true
}

locals {
  cluster_name = data.terraform_remote_state.network.outputs.frontend_cluster_name
}

# Kubernetes provider - connects to EKS cluster using AWS CLI exec auth
# This allows Terraform to manage Kubernetes resources without requiring kubectl to be pre-configured
provider "kubernetes" {
  host                   = module.frontend_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.frontend_eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      local.cluster_name,
      "--region",
      var.aws_region
    ]
  }
}

#####################
# Frontend EKS Cluster (Control Plane Only)
#####################

module "frontend_eks" {
  source = "../../modules/eks-cluster"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = data.terraform_remote_state.network.outputs.frontend_vpc_id
  subnet_ids         = data.terraform_remote_state.network.outputs.frontend_infra_private_subnet_ids
  pod_subnet_ids     = data.terraform_remote_state.network.outputs.frontend_pod_private_subnet_ids
  availability_zones = data.terraform_remote_state.network.outputs.frontend_availability_zones
  region             = var.aws_region

  # Route53 configuration for ExternalDNS
  route53_zone_id   = data.terraform_remote_state.network.outputs.route53_zone_id
  route53_zone_name = data.terraform_remote_state.network.outputs.route53_zone_name

  # Aviatrix Controller onboarding - role ARN for EKS access
  aviatrix_controller_role_arn = var.aviatrix_controller_role_arn
  enable_aviatrix_onboarding   = true

  tags = {
    Environment = "demo"
    Cluster     = "frontend"
    Terraform   = "true"
  }
}

# NOTE: Route53 zone association is managed by the network layer (network-aviatrix/)
# The VPCs are automatically associated when the Route53 zone is created there.
# See network-aviatrix/main.tf for the aws_route53_zone_association resources.
