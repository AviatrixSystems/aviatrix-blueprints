# =============================================================================
# VPCs and subnets for the AgentCore VCA
#
# Design:
#   AgentCore spoke VPC (10.50.0.0/16) - hosts:
#     - Runtime subnet: private, where AgentCore creates per-session ENIs
#     - Endpoint subnet: private, where interface VPC endpoints (PrivateLink)
#       for bedrock-agentcore and bedrock-agentcore-control terminate
#     - Aviatrix GW subnet: public, where the spoke gateway attaches
#
#   Client spoke VPC (10.60.0.0/16) - hosts:
#     - Client subnet: private, where the invoker EC2 runs
#     - Aviatrix GW subnet: public, where the spoke gateway attaches
#
# Route tables for the private subnets are managed by the Aviatrix spoke
# gateway module (0.0.0.0/0 -> spoke GW ENI). We don't touch them here.
# =============================================================================

# -----------------------------------------------------------------------------
# AgentCore Spoke VPC
# -----------------------------------------------------------------------------

resource "aws_vpc" "agentcore" {
  cidr_block           = var.agentcore_spoke_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-agentcore-spoke"
  }
}

# Aviatrix gateway subnet (public, AZ1). The mc-spoke module expects a CIDR
# already carved out; it will create its own ENI here.
resource "aws_subnet" "agentcore_gw" {
  vpc_id                  = aws_vpc.agentcore.id
  cidr_block              = cidrsubnet(var.agentcore_spoke_cidr, 8, 0) # 10.50.0.0/24
  availability_zone       = local.azs[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-agentcore-gw"
  }
}

# Runtime subnet - private. AgentCore drops per-session ENIs here when the
# runtime is created in VPC mode. Subnet-based DCF SmartGroup matches traffic
# from this CIDR.
resource "aws_subnet" "agentcore_runtime" {
  vpc_id            = aws_vpc.agentcore.id
  cidr_block        = cidrsubnet(var.agentcore_spoke_cidr, 8, 10) # 10.50.10.0/24
  availability_zone = local.azs[0]

  tags = {
    Name = "${local.name_prefix}-agentcore-runtime"
    Role = "agentcore-runtime"
  }
}

# Endpoint subnet - private. Interface VPC endpoints land here.
resource "aws_subnet" "agentcore_endpoint" {
  vpc_id            = aws_vpc.agentcore.id
  cidr_block        = cidrsubnet(var.agentcore_spoke_cidr, 8, 20) # 10.50.20.0/24
  availability_zone = local.azs[0]

  tags = {
    Name = "${local.name_prefix}-agentcore-endpoint"
    Role = "agentcore-privatelink"
  }
}

# Internet gateway on the spoke VPC so the Aviatrix spoke gateway has a path
# to the internet after DCF inspection (single_ip_snat on the spoke GW handles
# source NAT; no separate NAT Gateway is needed).
resource "aws_internet_gateway" "agentcore" {
  vpc_id = aws_vpc.agentcore.id

  tags = {
    Name = "${local.name_prefix}-agentcore-igw"
  }
}

resource "aws_route_table" "agentcore_public" {
  vpc_id = aws_vpc.agentcore.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.agentcore.id
  }

  tags = {
    Name = "${local.name_prefix}-agentcore-public-rt"
  }

  # The Aviatrix spoke gateway inserts additional routes into this table at
  # runtime. Ignore those so TF doesn't fight the controller.
  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table_association" "agentcore_gw" {
  subnet_id      = aws_subnet.agentcore_gw.id
  route_table_id = aws_route_table.agentcore_public.id
}

# -----------------------------------------------------------------------------
# Client Spoke VPC
# -----------------------------------------------------------------------------

resource "aws_vpc" "client" {
  cidr_block           = var.client_spoke_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-client-spoke"
  }
}

resource "aws_subnet" "client_gw" {
  vpc_id                  = aws_vpc.client.id
  cidr_block              = cidrsubnet(var.client_spoke_cidr, 8, 0) # 10.60.0.0/24
  availability_zone       = local.azs[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-client-gw"
  }
}

resource "aws_subnet" "client_workload" {
  vpc_id            = aws_vpc.client.id
  cidr_block        = cidrsubnet(var.client_spoke_cidr, 8, 10) # 10.60.10.0/24
  availability_zone = local.azs[0]

  tags = {
    Name = "${local.name_prefix}-client-workload"
    Role = "client-invoker"
  }
}

# Second public subnet in AZ[1] for the UI ALB. ALB requires >= 2 AZs
# even when there's a single target. Associated with the public RT so
# ALB nodes have internet return paths to client source IPs.
resource "aws_subnet" "client_alb_b" {
  vpc_id                  = aws_vpc.client.id
  cidr_block              = cidrsubnet(var.client_spoke_cidr, 8, 1) # 10.60.1.0/24
  availability_zone       = local.azs[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-client-alb-b"
    Role = "ui-alb"
  }
}

resource "aws_route_table_association" "client_alb_b" {
  subnet_id      = aws_subnet.client_alb_b.id
  route_table_id = aws_route_table.client_public.id
}

resource "aws_internet_gateway" "client" {
  vpc_id = aws_vpc.client.id

  tags = {
    Name = "${local.name_prefix}-client-igw"
  }
}

resource "aws_route_table" "client_public" {
  vpc_id = aws_vpc.client.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.client.id
  }

  tags = {
    Name = "${local.name_prefix}-client-public-rt"
  }

  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table_association" "client_gw" {
  subnet_id      = aws_subnet.client_gw.id
  route_table_id = aws_route_table.client_public.id
}
