resource "aws_vpc" "runner" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "vpc-${local.name_prefix}-spoke"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.runner.id

  tags = merge(local.common_tags, {
    Name = "igw-${local.name_prefix}"
  })
}

resource "aws_subnet" "gw" {
  vpc_id                  = aws_vpc.runner.id
  cidr_block              = var.gw_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-gw-subnet"
  })
}

resource "aws_subnet" "runner" {
  vpc_id                  = aws_vpc.runner.id
  cidr_block              = var.runner_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-subnet"
  })
}

# Public route table: GW subnet egresses directly via the Internet Gateway.
# This is what the Aviatrix spoke gateway VM uses to reach the internet for
# control-plane + SNAT egress.
resource "aws_route_table" "gw" {
  vpc_id = aws_vpc.runner.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "rt-${local.name_prefix}-gw"
  })
}

# Private route table: runner subnet has no direct internet route. Aviatrix
# adds 0.0.0.0/0 -> spoke gateway ENI once the gateway is up, so all egress
# transits the gateway (DCF inspection + SNAT).
resource "aws_route_table" "runner" {
  vpc_id = aws_vpc.runner.id

  tags = merge(local.common_tags, {
    Name = "rt-${local.name_prefix}"
  })

  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table_association" "gw" {
  subnet_id      = aws_subnet.gw.id
  route_table_id = aws_route_table.gw.id
}

resource "aws_route_table_association" "runner" {
  subnet_id      = aws_subnet.runner.id
  route_table_id = aws_route_table.runner.id
}
