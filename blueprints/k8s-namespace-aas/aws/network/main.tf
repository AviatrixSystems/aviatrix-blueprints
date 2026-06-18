#####################
# Pattern B: Namespace-as-a-Service — AWS Network Layer (Layer 1)
#
# This layer provisions:
#   - Aviatrix Transit Gateway in AWS
#   - 1 shared cluster VPC (all teams share a single EKS cluster)
#   - 1 Aviatrix Spoke Gateway with custom SNAT for pod traffic
#   - Route53 Private Hosted Zone for internal DNS
#
# Architecture:
#   Transit GW (10.2.0.0/20)
#     └── Shared Cluster Spoke (10.10.0.0/16) - single EKS cluster for all teams
#
# Team isolation is enforced by DCF SmartGroups keyed on k8s_namespace,
# NOT by separate VPCs or Kubernetes RBAC alone.
# RBAC is NOT a hard security boundary — DCF is the primary network isolation.
#
# Pod Networking:
#   VPC CNI custom networking with pod CIDR 100.64.0.0/16.
#   Pods use non-routable secondary CIDR addresses. Aviatrix SNAT translates pod
#   traffic to spoke gateway IPs for east-west and egress flows.
#
# CRITICAL LESSONS LEARNED:
#   - excluded_advertised_spoke_routes goes on the TRANSIT module, NOT on spokes
#   - Gateways are Active/Active, not standby
#   - DCF sees POST-SNAT traffic — use VPC SmartGroups for source, hostname for dest
#####################

provider "aviatrix" {
  skip_version_validation = true
}

provider "aws" {
  region = var.aws_region
}

resource "random_id" "suffix" {
  count       = var.random_suffix ? 1 : 0
  byte_length = 2
}

locals {
  name_prefix      = var.random_suffix ? "${var.name_prefix}-${random_id.suffix[0].hex}" : var.name_prefix
  pod_cidr         = var.pod_cidr
  k8s_cluster_name = "${local.name_prefix}-${var.k8s_cluster_suffix}"
}

#####################
# Aviatrix Transit Gateway
#####################

module "aws_transit" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "~> 8.2.0"

  name    = "${local.name_prefix}-transit"
  cloud   = "AWS"
  account = var.aviatrix_aws_account_name
  region  = var.aws_region
  cidr    = var.transit_cidr
  ha_gw   = false

  # Enable FireNet for future NGFW integration
  enable_transit_firenet        = true
  enable_egress_transit_firenet = false

  instance_size     = "c5.xlarge"
  connected_transit = true

  # Use VPC DNS server for gateway management - required for hostname SmartGroups
  enable_vpc_dns_server = true

  # CRITICAL: Exclude non-routable pod CIDR from BGP advertisements
  # This is software-defined routing via Aviatrix, not BGP from spokes
  excluded_advertised_spoke_routes = local.pod_cidr
}

#####################
# Shared Cluster VPC
#
# Unlike Pattern A (Cluster-as-a-Service) which creates 1 VPC per team,
# Pattern B uses a single VPC for the shared cluster. All teams' namespaces
# run in the same EKS cluster within this VPC.
#####################

module "shared_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name_prefix}-shared-cluster"
  cidr = var.shared_vpc_cidr

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = [cidrsubnet(var.shared_vpc_cidr, 4, 1), cidrsubnet(var.shared_vpc_cidr, 4, 2)]
  public_subnets  = [cidrsubnet(var.shared_vpc_cidr, 4, 3), cidrsubnet(var.shared_vpc_cidr, 4, 4)]

  # Secondary CIDR for pods (VPC CNI custom networking)
  secondary_cidr_blocks = [local.pod_cidr]

  enable_nat_gateway = false # Aviatrix spoke handles NAT
  enable_vpn_gateway = false

  # Tags required for EKS auto-discovery
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  tags = {
    Environment = var.env
    Pattern     = "namespace-aas"
    Terraform   = "true"
  }
}

# Pod subnets in the secondary CIDR (100.64.0.0/16)
resource "aws_subnet" "pods" {
  count             = 2
  vpc_id            = module.shared_vpc.vpc_id
  cidr_block        = cidrsubnet(local.pod_cidr, 2, count.index)
  availability_zone = ["${var.aws_region}a", "${var.aws_region}b"][count.index]

  depends_on = [module.shared_vpc]

  tags = {
    Name        = "${local.name_prefix}-shared-pods-${["a", "b"][count.index]}"
    Environment = var.env
    Pattern     = "namespace-aas"
    Terraform   = "true"
  }
}

#####################
# Spoke Gateway (Shared Cluster VPC)
#####################

module "shared_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud      = "AWS"
  name       = "${local.name_prefix}-shared-spoke"
  account    = var.aviatrix_aws_account_name
  region     = var.aws_region
  transit_gw = module.aws_transit.transit_gateway.gw_name

  # Active/Active gateways — NOT standby
  instance_size = "t3.medium"
  ha_gw         = false

  enable_vpc_dns_server = true

  # Use existing VPC
  use_existing_vpc = true
  vpc_id           = module.shared_vpc.vpc_id
  gw_subnet        = module.shared_vpc.public_subnets_cidr_blocks[0]
  hagw_subnet      = module.shared_vpc.public_subnets_cidr_blocks[1]
}

# CRITICAL: Custom SNAT for pod traffic (100.64.0.0/16 -> spoke gateway IP)
#
# Why SNAT is needed:
#   VPC CNI custom networking pods use non-routable addresses (100.64.x.x).
#   Aviatrix transit cannot route these overlapping CIDRs.
#   SNAT translates pod source IPs to the spoke gateway IP, making traffic
#   routable across the Aviatrix transit fabric.
#
# DCF sees POST-SNAT traffic, so use VPC SmartGroups for source matching.
resource "aviatrix_gateway_snat" "shared_spoke_snat" {
  gw_name   = module.shared_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  # SNAT for pod-to-pod traffic within the cluster (intra-VPC)
  # Forces pod east-west traffic through the spoke gateway so DCF can
  # enforce namespace isolation rules on intra-cluster traffic.
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = local.pod_cidr
    protocol   = "all"
    interface  = ""
    connection = module.aws_transit.transit_gateway.gw_name
    snat_ips   = module.shared_spoke.spoke_gateway.private_ip
  }

  # SNAT for pod CIDR to all destinations via transit (east-west to other VPCs)
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.aws_transit.transit_gateway.gw_name
    snat_ips   = module.shared_spoke.spoke_gateway.private_ip
  }

  # SNAT for pod CIDR to internet via eth0
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.shared_spoke.spoke_gateway.private_ip
  }

  # SNAT for EKS node subnet to internet
  snat_policy {
    src_cidr   = var.shared_vpc_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.shared_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.shared_spoke]
}

#####################
# Route53 Private Hosted Zone
#####################

resource "aws_route53_zone" "private" {
  name = var.private_dns_zone_name

  vpc {
    vpc_id = module.shared_vpc.vpc_id
  }

  tags = {
    Environment = var.env
    Pattern     = "namespace-aas"
    Terraform   = "true"
  }

  # Ignore VPC associations managed outside Terraform
  lifecycle {
    ignore_changes = [vpc]
  }
}

# Associate transit VPC with the private hosted zone
resource "aws_route53_zone_association" "transit" {
  zone_id = aws_route53_zone.private.zone_id
  vpc_id  = module.aws_transit.vpc.vpc_id
}
