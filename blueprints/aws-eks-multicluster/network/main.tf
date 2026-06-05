terraform {
  required_version = ">= 1.5"

  required_providers {
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2.0"
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
  secondary_cidr = var.pod_cidr

  # Cluster configurations
  clusters = {
    frontend = {
      name         = "${var.name_prefix}-frontend"
      primary_cidr = var.frontend_vpc_cidr
    }
    backend = {
      name         = "${var.name_prefix}-backend"
      primary_cidr = var.backend_vpc_cidr
    }
  }
}

#####################
# Aviatrix Transit Gateway
#####################

module "aws_transit" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "~> 8.2.0"

  name    = "${var.name_prefix}-transit"
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
  # and resolving private DNS records (e.g., Route53 private hosted zones)
  enable_vpc_dns_server = true

  # CRITICAL: Exclude non-routable pod CIDR from BGP advertisements
  # This allows multiple spokes with the same secondary CIDR (100.64.0.0/16)
  excluded_advertised_spoke_routes = local.secondary_cidr
}

# NOTE: Spoke gateways are named "${var.name}-spoke" by the shared module, so
# they are "frontend-spoke" / "backend-spoke" here (var.name is kept bare so the
# VPC Name tag keeps matching the DCF VPC SmartGroups in dcf.tf). This is a rename
# relative to any pre-refactor deployment, which used "${name_prefix}-frontend-spoke".
# The shared module also splits the old single private route table into two
# (infra_private + pod_private), so route-table resource IDs change as well.
# Upgrading an existing network state therefore requires `terraform state mv` or a
# destroy + apply of this layer (this is a new deployment otherwise).

#####################
# Frontend VPC and Spoke (aws-eks-spoke-vpc, aviatrix transit mode)
#####################

module "frontend_vpc" {
  source = "../../../modules/aws-eks-spoke-vpc"

  name                      = "frontend" # VPC Name tag -> DCF VPC SmartGroup match
  cluster_name              = local.clusters.frontend.name
  primary_cidr              = local.clusters.frontend.primary_cidr
  pod_cidr                  = local.secondary_cidr
  region                    = var.aws_region
  aviatrix_aws_account_name = var.aviatrix_aws_account_name

  transit_type    = "aviatrix"
  transit_gw_name = module.aws_transit.transit_gateway.gw_name

  tags = {
    Environment = "demo"
    Cluster     = "frontend"
    Terraform   = "true"
  }
}

#####################
# Backend VPC and Spoke (aws-eks-spoke-vpc, aviatrix transit mode)
#####################

module "backend_vpc" {
  source = "../../../modules/aws-eks-spoke-vpc"

  name                      = "backend" # VPC Name tag -> DCF VPC SmartGroup match
  cluster_name              = local.clusters.backend.name
  primary_cidr              = local.clusters.backend.primary_cidr
  pod_cidr                  = local.secondary_cidr
  region                    = var.aws_region
  aviatrix_aws_account_name = var.aviatrix_aws_account_name

  transit_type    = "aviatrix"
  transit_gw_name = module.aws_transit.transit_gateway.gw_name

  tags = {
    Environment = "demo"
    Cluster     = "backend"
    Terraform   = "true"
  }
}

#####################
# Database Spoke (Apache VM)
#####################

module "spoke_db" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud          = "AWS"
  name           = "${var.name_prefix}-db-spoke"
  cidr           = var.db_vpc_cidr
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
  subnet_id          = module.spoke_db.vpc.private_subnets[0].subnet_id
  security_group_ids = [aws_security_group.eice_db.id]
}

resource "aws_security_group" "eice_db" {
  name        = "${var.name_prefix}-eice-db"
  description = "Security group for EC2 Instance Connect Endpoint"
  vpc_id      = module.spoke_db.vpc.vpc_id

  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "db" {
  source = "./modules/apache-vm"

  name_prefix             = var.name_prefix
  vpc_id                  = module.spoke_db.vpc.vpc_id
  subnet_id               = module.spoke_db.vpc.private_subnets[0].subnet_id
  region                  = var.aws_region
  eice_security_group_ids = [aws_security_group.eice_db.id]
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

