provider "aws" {
  region = var.aws_region
}

# Aviatrix provider - uses environment variables for authentication:
# AVIATRIX_CONTROLLER_IP, AVIATRIX_USERNAME, AVIATRIX_PASSWORD
provider "aviatrix" {
  skip_version_validation = true
}

locals {
  cluster_name = data.terraform_remote_state.network.outputs.cluster_name
}

# Kubernetes provider - connects to EKS cluster using AWS CLI exec auth
# This allows Terraform to manage Kubernetes resources without requiring kubectl to be pre-configured
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

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
# EKS Cluster (Control Plane Only)
#####################

module "eks" {
  source = "../../../modules/aws-eks-cluster"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids         = data.terraform_remote_state.network.outputs.infra_private_subnet_ids
  pod_subnet_ids     = data.terraform_remote_state.network.outputs.pod_private_subnet_ids
  availability_zones = data.terraform_remote_state.network.outputs.availability_zones
  region             = var.aws_region

  # Aviatrix Controller onboarding - role ARN for EKS access
  aviatrix_controller_role_arn = var.aviatrix_controller_role_arn
  enable_aviatrix_onboarding   = true

  tags = {
    Environment = "demo"
    Terraform   = "true"
  }
}
