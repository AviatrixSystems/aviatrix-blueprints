# =============================================================================
# VPC
# =============================================================================

locals {
  name = var.name_prefix
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = [
    cidrsubnet(var.vpc_cidr, 8, 1),
    cidrsubnet(var.vpc_cidr, 8, 2),
    cidrsubnet(var.vpc_cidr, 8, 3),
  ]
  public_subnets = [
    cidrsubnet(var.vpc_cidr, 8, 0), # Aviatrix spoke gateway
  ]

  tags = { project = local.name }

  # Placeholder CIDR (RFC 5737 TEST-NET-1) used when obot_system_pod_cidrs is
  # empty on first apply. The Aviatrix provider requires at least one
  # match_expressions block in a SmartGroup selector. This placeholder creates a
  # valid but non-matching group; it is replaced on second apply once real pod
  # IPs are supplied via Step 6.
  obot_system_pod_cidrs_effective = length(var.obot_system_pod_cidrs) > 0 ? var.obot_system_pod_cidrs : ["192.0.2.0/32"]
}

data "aws_availability_zones" "available" { state = "available" }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  # NAT GW not needed — Aviatrix spoke GW handles SNAT for pod egress.
  enable_nat_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  # EKS subnet discovery tags
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = 1
    "kubernetes.io/cluster/${local.name}-cluster" = "shared"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  tags = local.tags
}
