#####################
# VPC and Networking
#####################

locals {
  az_names = [
    "${var.aws_region}a",
    "${var.aws_region}b"
  ]

  cluster_name = "${var.name_prefix}-cluster"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name      = "${var.name_prefix}-vpc"
    Terraform = "true"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name      = "${var.name_prefix}-igw"
    Terraform = "true"
  }
}

###########################
# Route Tables
###########################

# Public route table for Aviatrix gateways
resource "aws_route_table" "avx_public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name      = "${var.name_prefix}-avx-public-rt"
    Type      = "aviatrix-gateway"
    Terraform = "true"
  }

  lifecycle {
    ignore_changes = [route]
  }
}

# Public route table for ALB
resource "aws_route_table" "lb_public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name      = "${var.name_prefix}-lb-public-rt"
    Type      = "load-balancer"
    Terraform = "true"
  }

  lifecycle {
    ignore_changes = [route]
  }
}

# Private route table (Aviatrix spoke gateway programs routes here)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name      = "${var.name_prefix}-private-rt"
    Type      = "private"
    Terraform = "true"
  }

  lifecycle {
    ignore_changes = [route]
  }
}

###########################
# Aviatrix Gateway Subnets (/28, public)
###########################

resource "aws_subnet" "avx_public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 12, count.index)
  availability_zone       = local.az_names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name      = "${var.name_prefix}-avx-public-${local.az_names[count.index]}"
    Type      = "aviatrix-gateway"
    Terraform = "true"
  }
}

resource "aws_route_table_association" "avx_public" {
  count          = 2
  subnet_id      = aws_subnet.avx_public[count.index].id
  route_table_id = aws_route_table.avx_public.id
}

###########################
# ALB Subnets (/24, public)
###########################

resource "aws_subnet" "lb_public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = local.az_names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                          = "${var.name_prefix}-lb-public-${local.az_names[count.index]}"
    Type                                          = "load-balancer"
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    Terraform                                     = "true"
  }
}

resource "aws_route_table_association" "lb_public" {
  count          = 2
  subnet_id      = aws_subnet.lb_public[count.index].id
  route_table_id = aws_route_table.lb_public.id
}

###########################
# EKS Node Subnets (/24, private)
###########################

resource "aws_subnet" "eks_private" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = local.az_names[count.index]

  tags = {
    Name                                          = "${var.name_prefix}-eks-private-${local.az_names[count.index]}"
    Type                                          = "infrastructure"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    Terraform                                     = "true"
  }
}

resource "aws_route_table_association" "eks_private" {
  count          = 2
  subnet_id      = aws_subnet.eks_private[count.index].id
  route_table_id = aws_route_table.private.id
}
