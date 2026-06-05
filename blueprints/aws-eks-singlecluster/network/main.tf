provider "aviatrix" {
  skip_version_validation = true
}

provider "aws" {
  region = var.aws_region
}

locals {
  cluster_name = "${var.name_prefix}-cluster"
}

module "spoke_vpc" {
  source = "../../../modules/aws-eks-spoke-vpc"

  name         = var.name_prefix
  cluster_name = local.cluster_name
  primary_cidr = var.vpc_cidr
  pod_cidr     = var.pod_cidr
  region       = var.aws_region

  aviatrix_aws_account_name = var.aviatrix_aws_account_name

  transit_type                  = var.transit_type
  pod_cidr_mode                 = var.pod_cidr_mode
  transit_gw_name               = var.transit_gw_name
  aws_tgw_id                    = var.aws_tgw_id
  aws_cloudwan_core_network_arn = var.aws_cloudwan_core_network_arn

  tags = {
    Environment = "demo"
    Blueprint   = "aws-eks-singlecluster"
    Terraform   = "true"
  }
}
