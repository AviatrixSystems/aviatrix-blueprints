terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  az_names = [
    "${var.region}a",
    "${var.region}b"
  ]
}

# Primary VPC
resource "aws_vpc" "this" {
  cidr_block           = var.primary_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = var.name
  })
}

# Secondary CIDR for pods (non-routable, overlapping across VPCs)
resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  vpc_id     = aws_vpc.this.id
  cidr_block = var.secondary_cidr
}

# Internet Gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}

# Public Route Table - Aviatrix Gateways
resource "aws_route_table" "avx_public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-avx-public-rt"
    Type = "aviatrix-gateway"
  })

  lifecycle {
    ignore_changes = [route] # Aviatrix controller manages RFC1918 routes via spoke gateway
  }
}

# Public Route Table - Load Balancers
resource "aws_route_table" "lb_public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-lb-public-rt"
    Type = "load-balancer"
  })

  lifecycle {
    ignore_changes = [route] # Aviatrix controller manages RFC1918 routes via spoke gateway
  }
}

# Private Route Table (will be updated by Aviatrix spoke gateway)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-private-rt"
    Type = "private"
  })

  lifecycle {
    ignore_changes = [route] # Aviatrix will manage routes
  }
}

###########################
# Aviatrix Gateway Subnets
###########################

# Public subnets for Aviatrix Spoke Gateways (/28 = 16 IPs each)
resource "aws_subnet" "avx_public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.primary_cidr, 5, count.index) # First two /28 subnets
  availability_zone       = local.az_names[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name}-avx-public-${local.az_names[count.index]}"
    Type = "aviatrix-gateway"
  })
}

resource "aws_route_table_association" "avx_public" {
  count          = 2
  subnet_id      = aws_subnet.avx_public[count.index].id
  route_table_id = aws_route_table.avx_public.id
}

###########################
# Load Balancer Subnets
###########################

# Public subnets for ALB/NLB (/26 = 64 IPs each)
resource "aws_subnet" "lb_public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.primary_cidr, 3, count.index + 1) # /26, offset to avoid overlap with /28
  availability_zone       = local.az_names[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                        = "${var.name}-lb-public-${local.az_names[count.index]}"
    Type                                        = "load-balancer"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_route_table_association" "lb_public" {
  count          = 2
  subnet_id      = aws_subnet.lb_public[count.index].id
  route_table_id = aws_route_table.lb_public.id
}

###########################
# Infrastructure Subnets
###########################

# Private subnets for EKS nodes and control plane ENIs (/26 = 64 IPs each)
resource "aws_subnet" "infra_private" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.primary_cidr, 3, count.index + 5) # /26, higher offset
  availability_zone = local.az_names[count.index]

  tags = merge(var.tags, {
    Name                                        = "${var.name}-infra-private-${local.az_names[count.index]}"
    Type                                        = "infrastructure"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_route_table_association" "infra_private" {
  count          = 2
  subnet_id      = aws_subnet.infra_private[count.index].id
  route_table_id = aws_route_table.private.id
}

###########################
# Pod Subnets (Secondary CIDR)
###########################

# Private subnets for EKS pods from secondary CIDR (/17 = 32,768 IPs each)
resource "aws_subnet" "pod_private" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.secondary_cidr, 1, count.index) # Split secondary CIDR in half
  availability_zone = local.az_names[count.index]

  tags = merge(var.tags, {
    Name                                        = "${var.name}-pod-private-${local.az_names[count.index]}"
    Type                                        = "pod"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })

  depends_on = [aws_vpc_ipv4_cidr_block_association.secondary]
}

resource "aws_route_table_association" "pod_private" {
  count          = 2
  subnet_id      = aws_subnet.pod_private[count.index].id
  route_table_id = aws_route_table.private.id
}
