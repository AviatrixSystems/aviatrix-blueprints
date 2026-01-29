# =============================================================================
# Blueprint: [Blueprint Name]
# Description: [Brief description of what this blueprint deploys]
# =============================================================================

# -----------------------------------------------------------------------------
# Aviatrix Provider Configuration
# -----------------------------------------------------------------------------
provider "aviatrix" {
  controller_ip           = var.controller_ip
  username                = var.controller_username
  password                = var.controller_password
  skip_version_validation = false
}

# -----------------------------------------------------------------------------
# AWS Provider Configuration
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Blueprint   = var.name_prefix
      Environment = "lab"
      ManagedBy   = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# Example: Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Example: Get latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------
locals {
  # Common naming
  name_prefix = var.name_prefix

  # Availability zones (use first 2)
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Common tags (in addition to default_tags)
  common_tags = {
    Blueprint = var.name_prefix
  }
}

# -----------------------------------------------------------------------------
# VPC Resources
# -----------------------------------------------------------------------------

# Example VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# Example Subnet
resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${count.index + 1}"
  }
}

# -----------------------------------------------------------------------------
# Aviatrix Resources
# -----------------------------------------------------------------------------

# Example: Aviatrix Spoke Gateway
# resource "aviatrix_spoke_gateway" "example" {
#   cloud_type         = 1  # AWS
#   account_name       = var.aviatrix_account_name
#   gw_name            = "${local.name_prefix}-spoke"
#   vpc_id             = aws_vpc.main.id
#   vpc_reg            = var.aws_region
#   gw_size            = var.gateway_size
#   subnet             = aws_subnet.public[0].cidr_block
#   single_ip_snat     = false
#   manage_transit_gateway_attachment = false
# }

# -----------------------------------------------------------------------------
# Test Resources
# -----------------------------------------------------------------------------

# Example: Test EC2 instance
# resource "aws_instance" "test" {
#   ami                    = data.aws_ami.amazon_linux_2.id
#   instance_type          = "t3.micro"
#   subnet_id              = aws_subnet.public[0].id
#   vpc_security_group_ids = [aws_security_group.test.id]
#
#   tags = {
#     Name = "${local.name_prefix}-test"
#   }
# }
