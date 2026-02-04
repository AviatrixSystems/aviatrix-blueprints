terraform {
  required_version = ">= 1.5"

  required_providers {
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aviatrix" {
  skip_version_validation = true
}

provider "aws" {
  region = var.aws_region
}

locals {
  # Non-routable secondary CIDR for pods - same across all VPCs (overlapping)
  secondary_cidr = "100.64.0.0/16"

  # Cluster configurations
  clusters = {
    frontend = {
      name         = "frontend-cluster"
      primary_cidr = "10.10.0.0/23"
    }
    backend = {
      name         = "backend-cluster"
      primary_cidr = "10.20.0.0/23"
    }
  }
}

#####################
# Aviatrix Transit Gateway
#####################

module "aws_transit" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "~> 8.0"

  name    = "k8s-transit"
  cloud   = "AWS"
  account = var.aviatrix_aws_account_name
  region  = var.aws_region
  cidr    = "10.2.0.0/20"
  ha_gw   = false

  # Enable FireNet for future NGFW integration
  enable_transit_firenet        = true
  enable_egress_transit_firenet = false

  instance_size     = "t3.medium"
  connected_transit = true

  # Use VPC DNS server for gateway management - required for hostname SmartGroups
  # and resolving private DNS records (e.g., Route53 private hosted zones)
  enable_vpc_dns_server = true

  # CRITICAL: Exclude non-routable pod CIDR from BGP advertisements
  # This allows multiple spokes with the same secondary CIDR (100.64.0.0/16)
  excluded_advertised_spoke_routes = local.secondary_cidr
}

#####################
# Frontend VPC and Spoke
#####################

module "frontend_vpc" {
  source = "./modules/eks-vpc"

  name           = "frontend"
  cluster_name   = local.clusters.frontend.name
  primary_cidr   = local.clusters.frontend.primary_cidr
  secondary_cidr = local.secondary_cidr
  region         = var.aws_region

  tags = {
    Environment = "demo"
    Cluster     = "frontend"
    Terraform   = "true"
  }
}

module "frontend_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  cloud      = "AWS"
  name       = "frontend-eks-spoke"
  account    = var.aviatrix_aws_account_name
  region     = var.aws_region
  transit_gw = module.aws_transit.transit_gateway.gw_name

  instance_size = "t3.medium"
  ha_gw         = false

  # Use VPC DNS server for gateway management - required for hostname SmartGroups
  # and resolving private DNS records (e.g., Route53 private hosted zones)
  enable_vpc_dns_server = true

  # Use existing VPC created by eks-vpc module
  use_existing_vpc = true
  vpc_id           = module.frontend_vpc.vpc_id
  gw_subnet        = module.frontend_vpc.avx_gateway_subnet_cidrs[0]
  hagw_subnet      = module.frontend_vpc.avx_gateway_subnet_cidrs[1]

  skip_public_route_table_update = false
}

# CRITICAL: Custom SNAT for pod traffic (100.64.0.0/16 → spoke gateway IP)
resource "aviatrix_gateway_snat" "frontend_spoke_snat" {
  gw_name   = module.frontend_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  # SNAT for pod CIDR to all destinations via transit
  snat_policy {
    src_cidr   = local.secondary_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.aws_transit.transit_gateway.gw_name
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  # SNAT for pod CIDR to internet via eth0
  snat_policy {
    src_cidr   = local.secondary_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  # SNAT for private infrastructure subnets (EKS nodes) to internet
  dynamic "snat_policy" {
    for_each = module.frontend_vpc.infra_private_subnet_cidrs
    content {
      src_cidr   = snat_policy.value
      dst_cidr   = "0.0.0.0/0"
      protocol   = "all"
      interface  = "eth0"
      connection = ""
      snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
    }
  }

  depends_on = [module.frontend_spoke]
}

#####################
# Backend VPC and Spoke
#####################

module "backend_vpc" {
  source = "./modules/eks-vpc"

  name           = "backend"
  cluster_name   = local.clusters.backend.name
  primary_cidr   = local.clusters.backend.primary_cidr
  secondary_cidr = local.secondary_cidr
  region         = var.aws_region

  tags = {
    Environment = "demo"
    Cluster     = "backend"
    Terraform   = "true"
  }
}

module "backend_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  cloud      = "AWS"
  name       = "backend-eks-spoke"
  account    = var.aviatrix_aws_account_name
  region     = var.aws_region
  transit_gw = module.aws_transit.transit_gateway.gw_name

  instance_size = "t3.medium"
  ha_gw         = false

  # Use VPC DNS server for gateway management - required for hostname SmartGroups
  # and resolving private DNS records (e.g., Route53 private hosted zones)
  enable_vpc_dns_server = true

  # Use existing VPC created by eks-vpc module
  use_existing_vpc = true
  vpc_id           = module.backend_vpc.vpc_id
  gw_subnet        = module.backend_vpc.avx_gateway_subnet_cidrs[0]
  hagw_subnet      = module.backend_vpc.avx_gateway_subnet_cidrs[1]

  skip_public_route_table_update = false
}

# CRITICAL: Custom SNAT for pod traffic (100.64.0.0/16 → spoke gateway IP)
resource "aviatrix_gateway_snat" "backend_spoke_snat" {
  gw_name   = module.backend_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  # SNAT for pod CIDR to all destinations via transit
  snat_policy {
    src_cidr   = local.secondary_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.aws_transit.transit_gateway.gw_name
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  # SNAT for pod CIDR to internet via eth0
  snat_policy {
    src_cidr   = local.secondary_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  # SNAT for private infrastructure subnets (EKS nodes) to internet
  dynamic "snat_policy" {
    for_each = module.backend_vpc.infra_private_subnet_cidrs
    content {
      src_cidr   = snat_policy.value
      dst_cidr   = "0.0.0.0/0"
      protocol   = "all"
      interface  = "eth0"
      connection = ""
      snat_ips   = module.backend_spoke.spoke_gateway.private_ip
    }
  }

  depends_on = [module.backend_spoke]
}

#####################
# Database Spoke (Apache VM)
#####################

module "spoke_db" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  cloud          = "AWS"
  name           = "k8s-demo-db"
  cidr           = "10.5.0.0/22"
  account        = var.aviatrix_aws_account_name
  region         = var.aws_region
  transit_gw     = module.aws_transit.transit_gateway.gw_name
  instance_size  = "t3.medium"
  ha_gw          = false
  single_ip_snat = true

  # Use VPC DNS server for gateway management - required for hostname SmartGroups
  # and resolving private DNS records (e.g., Route53 private hosted zones)
  enable_vpc_dns_server = true
}

resource "aws_ec2_instance_connect_endpoint" "db_instance_connect" {
  subnet_id = module.spoke_db.vpc.private_subnets[0].subnet_id
}

module "db" {
  source = "./modules/apache-vm"

  vpc_id    = module.spoke_db.vpc.vpc_id
  subnet_id = module.spoke_db.vpc.private_subnets[0].subnet_id
  region    = var.aws_region
}

#####################
# Route53 Private Hosted Zone
#####################

# Create private hosted zone - use DB VPC as primary
resource "aws_route53_zone" "private" {
  name = var.route53_private_zone_name

  # Primary VPC association (required during creation)
  vpc {
    vpc_id = module.spoke_db.vpc.vpc_id
  }

  tags = {
    Name        = var.route53_private_zone_name
    Environment = "demo"
    Terraform   = "true"
  }

  # Additional VPCs are associated via aws_route53_zone_association resources.
  # Ignore inline vpc changes to prevent conflict with those resources.
  lifecycle {
    ignore_changes = [vpc]
  }
}

# Associate with transit VPC
resource "aws_route53_zone_association" "transit" {
  zone_id = aws_route53_zone.private.zone_id
  vpc_id  = module.aws_transit.vpc.vpc_id
}

resource "aws_route53_zone_association" "frontend" {
  zone_id = aws_route53_zone.private.zone_id
  vpc_id  = module.frontend_vpc.vpc_id
}

resource "aws_route53_zone_association" "backend" {
  zone_id = aws_route53_zone.private.zone_id
  vpc_id  = module.backend_vpc.vpc_id
}

#####################
# Static DNS Records
#####################

# Database VM record
resource "aws_route53_record" "db" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "db.${var.route53_private_zone_name}"
  type    = "A"
  ttl     = 300
  records = [module.db.vm_private_ip]
}

