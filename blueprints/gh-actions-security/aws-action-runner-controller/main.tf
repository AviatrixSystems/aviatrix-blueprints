provider "aws" {
  region = var.aws_region
}

# Aviatrix credentials come from TF_VAR_* environment variables — never set in tfvars.
provider "aviatrix" {
  controller_ip           = var.aviatrix_controller_ip
  username                = var.aviatrix_username
  password                = var.aviatrix_password
  skip_version_validation = true
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

resource "random_integer" "deployment_id" {
  min = 100000
  max = 999999
}

locals {
  name_prefix = "${var.name_prefix}-${random_integer.deployment_id.result}"

  common_tags = {
    blueprint = "gh-pipeline-sec"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Resolves the source IAM role when the caller is an assumed-role session
# (SSO, CI, etc.). issuer_arn is the role ARN; for plain IAM users it equals
# the caller ARN. This is added to access_entries so whoever runs terraform
# always gets cluster-admin without having to hardcode their own ARN.
data "aws_iam_session_context" "deployer" {
  arn = data.aws_caller_identity.current.arn
}

