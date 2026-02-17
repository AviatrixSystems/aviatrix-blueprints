locals {
  common_tags = {
    Blueprint   = "zero-trust-segmentation"
    ManagedBy   = "Terraform"
    Environment = "Demo"
    Owner       = var.name_prefix
  }
}

# Get latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ============================================================================
# Transit Gateway and VPC
# ============================================================================

resource "aws_vpc" "transit" {
  cidr_block           = var.transit_gateway.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-transit-vpc"
  })
}

resource "aws_subnet" "transit_public" {
  vpc_id                  = aws_vpc.transit.id
  cidr_block              = cidrsubnet(var.transit_gateway.cidr, 2, 0)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-transit-public-subnet"
  })
}

resource "aws_internet_gateway" "transit" {
  vpc_id = aws_vpc.transit.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-transit-igw"
  })
}

resource "aws_route_table" "transit_public" {
  vpc_id = aws_vpc.transit.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.transit.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-transit-public-rt"
  })
}

resource "aws_route_table_association" "transit_public" {
  subnet_id      = aws_subnet.transit_public.id
  route_table_id = aws_route_table.transit_public.id
}

# Aviatrix Transit Gateway
resource "aviatrix_transit_gateway" "main" {
  cloud_type   = 1 # AWS
  account_name = var.aws_account_name
  gw_name      = "${var.name_prefix}-transit-gw"
  vpc_id       = aws_vpc.transit.id
  vpc_reg      = var.aws_region
  gw_size      = "t3.small"
  subnet       = aws_subnet.transit_public.cidr_block
  ha_subnet    = var.transit_gateway.ha_enabled ? cidrsubnet(var.transit_gateway.cidr, 2, 1) : null
  ha_gw_size   = var.transit_gateway.ha_enabled ? "t3.small" : null

  local_as_number                      = var.transit_gateway.asn
  enable_segmentation                  = true
  enable_transit_firenet               = false
  connected_transit                    = true
  enable_advertise_transit_cidr        = true
  enable_active_standby                = false
  enable_gateway_load_balancer         = false
  enable_vpc_dns_server                = false
  enable_encrypt_volume                = true
  enable_preserve_as_path              = false
  enable_bgp_over_lan                  = false

  tags = local.common_tags
}

# ============================================================================
# Spoke Gateways and VPCs
# ============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "spokes" {
  for_each = var.spokes

  cidr_block           = each.value.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-${each.key}-vpc"
    Environment = each.value.environment
  })
}

resource "aws_subnet" "spokes_public" {
  for_each = var.spokes

  vpc_id                  = aws_vpc.spokes[each.key].id
  cidr_block              = cidrsubnet(each.value.cidr, 2, 0)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-${each.key}-public-subnet"
    Environment = each.value.environment
  })
}

resource "aws_subnet" "spokes_private" {
  for_each = var.spokes

  vpc_id            = aws_vpc.spokes[each.key].id
  cidr_block        = cidrsubnet(each.value.cidr, 2, 1)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-${each.key}-private-subnet"
    Environment = each.value.environment
  })
}

resource "aws_internet_gateway" "spokes" {
  for_each = var.spokes

  vpc_id = aws_vpc.spokes[each.key].id

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-${each.key}-igw"
    Environment = each.value.environment
  })
}

resource "aws_route_table" "spokes_public" {
  for_each = var.spokes

  vpc_id = aws_vpc.spokes[each.key].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.spokes[each.key].id
  }

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-${each.key}-public-rt"
    Environment = each.value.environment
  })
}

resource "aws_route_table_association" "spokes_public" {
  for_each = var.spokes

  subnet_id      = aws_subnet.spokes_public[each.key].id
  route_table_id = aws_route_table.spokes_public[each.key].id
}

# Aviatrix Spoke Gateways
resource "aviatrix_spoke_gateway" "spokes" {
  for_each = var.spokes

  cloud_type   = 1 # AWS
  account_name = var.aws_account_name
  gw_name      = "${var.name_prefix}-${each.key}-spoke-gw"
  vpc_id       = aws_vpc.spokes[each.key].id
  vpc_reg      = var.aws_region
  gw_size      = "t3.small"
  subnet       = aws_subnet.spokes_public[each.key].cidr_block

  transit_gw = aviatrix_transit_gateway.main.gw_name

  enable_encrypt_volume = true
  enable_active_standby = false

  tags = merge(local.common_tags, {
    Environment = each.value.environment
  })
}

# ============================================================================
# Test VMs (one per spoke)
# ============================================================================

resource "aws_security_group" "test_vms" {
  for_each = var.spokes

  name_prefix = "${var.name_prefix}-${each.key}-vm-sg"
  description = "Security group for ${each.key} test VM"
  vpc_id      = aws_vpc.spokes[each.key].id

  # Allow SSH from anywhere (for demo purposes)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # Allow ICMP (ping) from anywhere
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "ICMP ping"
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-${each.key}-vm-sg"
    Environment = each.value.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "test_vms" {
  for_each = var.spokes

  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.test_vm_instance_type
  key_name               = var.test_vm_key_name
  subnet_id              = aws_subnet.spokes_private[each.key].id
  vpc_security_group_ids = [aws_security_group.test_vms[each.key].id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y tcpdump netcat nmap
              hostnamectl set-hostname ${each.key}-test-vm
              echo "Welcome to ${each.key} test VM" > /etc/motd
              EOF

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-${each.key}-test-vm"
    Environment = each.value.environment
    Role        = "test-instance"
  })
}
