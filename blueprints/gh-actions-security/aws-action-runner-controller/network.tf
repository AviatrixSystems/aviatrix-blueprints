resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "vpc-${local.name_prefix}-spoke"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "igw-${local.name_prefix}"
  })
}

# Public subnet for Aviatrix spoke gateway.
resource "aws_subnet" "gw" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.gw_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-gw-subnet"
  })
}

# EKS requires subnets in at least 2 AZs. Primary pods/nodes use [0], secondary [1].
resource "aws_subnet" "eks_primary" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.eks_primary_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(local.common_tags, {
    Name                                         = "${local.name_prefix}-eks-primary"
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/${local.name_prefix}" = "owned"
  })
}

resource "aws_subnet" "eks_secondary" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.eks_secondary_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = merge(local.common_tags, {
    Name                                         = "${local.name_prefix}-eks-secondary"
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/${local.name_prefix}" = "owned"
  })
}

# Public RT for Aviatrix spoke gateway — egresses via IGW.
resource "aws_route_table" "gw" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "rt-${local.name_prefix}-gw"
  })
}

# Private RT for EKS subnets — no direct internet route. Aviatrix programs
# 0.0.0.0/0 → spoke GW ENI once the gateway is up (via single_ip_snat).
resource "aws_route_table" "eks" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "rt-${local.name_prefix}-eks"
  })

  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table_association" "gw" {
  subnet_id      = aws_subnet.gw.id
  route_table_id = aws_route_table.gw.id
}

resource "aws_route_table_association" "eks_primary" {
  subnet_id      = aws_subnet.eks_primary.id
  route_table_id = aws_route_table.eks.id
}

resource "aws_route_table_association" "eks_secondary" {
  subnet_id      = aws_subnet.eks_secondary.id
  route_table_id = aws_route_table.eks.id
}
