#####################
# Pattern A: Cluster-as-a-Service - AWS Network Layer (Layer 1)
#
# This layer provisions:
#   - Aviatrix Transit Gateway in AWS
#   - 3x team VPCs (team-a, team-b, team-c) each with dedicated subnets
#   - 3x Aviatrix Spoke Gateways (active/active) with custom SNAT for pod traffic
#   - Database spoke VPC
#   - Route53 Private Hosted Zone for internal service discovery
#
# Architecture:
#   Transit GW (10.2.0.0/20)
#     ├── Team-A Spoke (10.10.0.0/20) - EKS cluster for team-a
#     ├── Team-B Spoke (10.11.0.0/20) - EKS cluster for team-b
#     ├── Team-C Spoke (10.12.0.0/20) - EKS cluster for team-c
#     └── Database Spoke (10.5.0.0/22) - Shared database
#
# Pod Networking:
#   VPC CNI custom networking with pod CIDR 100.64.0.0/16 (overlapping across VPCs).
#   Pods use non-routable secondary CIDR addresses. Aviatrix SNAT translates pod
#   traffic to spoke gateway IPs for east-west and egress flows.
#
# CRITICAL LESSONS LEARNED:
#   - excluded_advertised_spoke_routes goes on the TRANSIT module, NOT on spokes
#   - This is software-defined routing via Aviatrix, not BGP from spokes
#   - Gateways are Active/Active, not standby
#   - DCF sees POST-SNAT traffic -- use VPC SmartGroups for source, hostname for dest
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
  name_prefix = var.random_suffix ? "${var.name_prefix}-${random_id.suffix[0].hex}" : var.name_prefix
  pod_cidr    = var.pod_cidr

  teams = {
    team-a = {
      name     = "${local.name_prefix}-team-a"
      vpc_cidr = var.team_a_vpc_cidr
    }
    team-b = {
      name     = "${local.name_prefix}-team-b"
      vpc_cidr = var.team_b_vpc_cidr
    }
    team-c = {
      name     = "${local.name_prefix}-team-c"
      vpc_cidr = var.team_c_vpc_cidr
    }
  }
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
  # This goes on the TRANSIT module, NOT on spokes.
  # This allows multiple spokes with the same overlay CIDR (100.64.0.0/16).
  excluded_advertised_spoke_routes = local.pod_cidr
}

#####################
# Team-A VPC and Spoke
#####################

module "team_a_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name_prefix}-team-a"
  cidr = local.teams["team-a"].vpc_cidr

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = [cidrsubnet(local.teams["team-a"].vpc_cidr, 2, 1), cidrsubnet(local.teams["team-a"].vpc_cidr, 2, 2)]
  public_subnets  = [cidrsubnet(local.teams["team-a"].vpc_cidr, 4, 0), cidrsubnet(local.teams["team-a"].vpc_cidr, 4, 1)]

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
    Environment = "demo"
    Team        = "team-a"
    Terraform   = "true"
  }
}

# Pod subnets in the secondary CIDR (100.64.0.0/16)
resource "aws_subnet" "team_a_pods" {
  count             = 2
  vpc_id            = module.team_a_vpc.vpc_id
  cidr_block        = cidrsubnet(local.pod_cidr, 2, count.index)
  availability_zone = ["${var.aws_region}a", "${var.aws_region}b"][count.index]

  tags = {
    Name        = "${local.name_prefix}-team-a-pods-${["a", "b"][count.index]}"
    Environment = "demo"
    Team        = "team-a"
    Terraform   = "true"
  }
}

module "team_a_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud      = "AWS"
  name       = "${local.name_prefix}-team-a-spoke"
  account    = var.aviatrix_aws_account_name
  region     = var.aws_region
  transit_gw = module.aws_transit.transit_gateway.gw_name

  # Active/Active gateways - NOT standby
  instance_size = "t3.medium"
  ha_gw         = false

  enable_vpc_dns_server = true

  # Use existing VPC
  use_existing_vpc = true
  vpc_id           = module.team_a_vpc.vpc_id
  gw_subnet        = module.team_a_vpc.public_subnets_cidr_blocks[0]
  hagw_subnet      = module.team_a_vpc.public_subnets_cidr_blocks[1]
}

# CRITICAL: Custom SNAT for pod traffic (100.64.0.0/16 -> spoke gateway IP)
#
# Why SNAT is needed:
#   VPC CNI custom networking pods use non-routable addresses (100.64.x.x).
#   Aviatrix transit cannot route these overlapping CIDRs between spokes.
#   SNAT translates pod source IPs to the spoke gateway IP, making traffic
#   routable across the Aviatrix transit fabric.
#
# DCF sees POST-SNAT traffic, so use VPC SmartGroups for source matching.
resource "aviatrix_gateway_snat" "team_a_spoke_snat" {
  gw_name   = module.team_a_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  # SNAT for pod CIDR to all destinations via transit
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.aws_transit.transit_gateway.gw_name
    snat_ips   = module.team_a_spoke.spoke_gateway.private_ip
  }

  # SNAT for pod CIDR to internet via eth0
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_a_spoke.spoke_gateway.private_ip
  }

  # SNAT for EKS node subnet to internet
  snat_policy {
    src_cidr   = local.teams["team-a"].vpc_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_a_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.team_a_spoke]
}

#####################
# Team-B VPC and Spoke
#####################

module "team_b_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name_prefix}-team-b"
  cidr = local.teams["team-b"].vpc_cidr

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = [cidrsubnet(local.teams["team-b"].vpc_cidr, 2, 1), cidrsubnet(local.teams["team-b"].vpc_cidr, 2, 2)]
  public_subnets  = [cidrsubnet(local.teams["team-b"].vpc_cidr, 4, 0), cidrsubnet(local.teams["team-b"].vpc_cidr, 4, 1)]

  secondary_cidr_blocks = [local.pod_cidr]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  tags = {
    Environment = "demo"
    Team        = "team-b"
    Terraform   = "true"
  }
}

resource "aws_subnet" "team_b_pods" {
  count             = 2
  vpc_id            = module.team_b_vpc.vpc_id
  cidr_block        = cidrsubnet(local.pod_cidr, 2, count.index)
  availability_zone = ["${var.aws_region}a", "${var.aws_region}b"][count.index]

  tags = {
    Name        = "${local.name_prefix}-team-b-pods-${["a", "b"][count.index]}"
    Environment = "demo"
    Team        = "team-b"
    Terraform   = "true"
  }
}

module "team_b_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud      = "AWS"
  name       = "${local.name_prefix}-team-b-spoke"
  account    = var.aviatrix_aws_account_name
  region     = var.aws_region
  transit_gw = module.aws_transit.transit_gateway.gw_name

  instance_size = "t3.medium"
  ha_gw         = false

  enable_vpc_dns_server = true

  use_existing_vpc = true
  vpc_id           = module.team_b_vpc.vpc_id
  gw_subnet        = module.team_b_vpc.public_subnets_cidr_blocks[0]
  hagw_subnet      = module.team_b_vpc.public_subnets_cidr_blocks[1]
}

resource "aviatrix_gateway_snat" "team_b_spoke_snat" {
  gw_name   = module.team_b_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.aws_transit.transit_gateway.gw_name
    snat_ips   = module.team_b_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_b_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = local.teams["team-b"].vpc_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_b_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.team_b_spoke]
}

#####################
# Team-C VPC and Spoke
#####################

module "team_c_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name_prefix}-team-c"
  cidr = local.teams["team-c"].vpc_cidr

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = [cidrsubnet(local.teams["team-c"].vpc_cidr, 2, 1), cidrsubnet(local.teams["team-c"].vpc_cidr, 2, 2)]
  public_subnets  = [cidrsubnet(local.teams["team-c"].vpc_cidr, 4, 0), cidrsubnet(local.teams["team-c"].vpc_cidr, 4, 1)]

  secondary_cidr_blocks = [local.pod_cidr]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  tags = {
    Environment = "demo"
    Team        = "team-c"
    Terraform   = "true"
  }
}

resource "aws_subnet" "team_c_pods" {
  count             = 2
  vpc_id            = module.team_c_vpc.vpc_id
  cidr_block        = cidrsubnet(local.pod_cidr, 2, count.index)
  availability_zone = ["${var.aws_region}a", "${var.aws_region}b"][count.index]

  tags = {
    Name        = "${local.name_prefix}-team-c-pods-${["a", "b"][count.index]}"
    Environment = "demo"
    Team        = "team-c"
    Terraform   = "true"
  }
}

module "team_c_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud      = "AWS"
  name       = "${local.name_prefix}-team-c-spoke"
  account    = var.aviatrix_aws_account_name
  region     = var.aws_region
  transit_gw = module.aws_transit.transit_gateway.gw_name

  instance_size = "t3.medium"
  ha_gw         = false

  enable_vpc_dns_server = true

  use_existing_vpc = true
  vpc_id           = module.team_c_vpc.vpc_id
  gw_subnet        = module.team_c_vpc.public_subnets_cidr_blocks[0]
  hagw_subnet      = module.team_c_vpc.public_subnets_cidr_blocks[1]
}

resource "aviatrix_gateway_snat" "team_c_spoke_snat" {
  gw_name   = module.team_c_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.aws_transit.transit_gateway.gw_name
    snat_ips   = module.team_c_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_c_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = local.teams["team-c"].vpc_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_c_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.team_c_spoke]
}

#####################
# Database Spoke
#####################

module "spoke_db" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud          = "AWS"
  name           = "${local.name_prefix}-db-spoke"
  cidr           = var.db_vpc_cidr
  account        = var.aviatrix_aws_account_name
  region         = var.aws_region
  transit_gw     = module.aws_transit.transit_gateway.gw_name
  instance_size  = "t3.medium"
  ha_gw          = false
  single_ip_snat = true

  enable_vpc_dns_server = true
}

#####################
# Route53 Private Hosted Zone
#####################

resource "aws_route53_zone" "private" {
  name = var.private_dns_zone_name

  vpc {
    vpc_id = module.team_a_vpc.vpc_id
  }

  tags = {
    Environment = "demo"
    Terraform   = "true"
  }

  # Ignore VPC associations managed outside Terraform
  lifecycle {
    ignore_changes = [vpc]
  }
}

# Associate additional VPCs with the private hosted zone
resource "aws_route53_zone_association" "team_b" {
  zone_id = aws_route53_zone.private.zone_id
  vpc_id  = module.team_b_vpc.vpc_id
}

resource "aws_route53_zone_association" "team_c" {
  zone_id = aws_route53_zone.private.zone_id
  vpc_id  = module.team_c_vpc.vpc_id
}

resource "aws_route53_zone_association" "transit" {
  zone_id = aws_route53_zone.private.zone_id
  vpc_id  = module.aws_transit.vpc.vpc_id
}

#####################
# Static DNS Records
#####################

resource "aws_route53_record" "db" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "db.${var.private_dns_zone_name}"
  type    = "A"
  ttl     = 300
  records = [var.db_private_ip]
}
