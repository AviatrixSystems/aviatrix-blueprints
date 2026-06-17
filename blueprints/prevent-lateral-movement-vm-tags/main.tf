locals {
  common_tags = {
    Blueprint   = "prevent-lateral-movement-vm-tags"
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

resource "aws_subnet" "transit_ha" {
  count = var.transit_gateway.ha_enabled ? 1 : 0

  vpc_id                  = aws_vpc.transit.id
  cidr_block              = cidrsubnet(var.transit_gateway.cidr, 2, 1)
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-transit-ha-subnet"
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

resource "aws_route_table_association" "transit_ha" {
  count = var.transit_gateway.ha_enabled ? 1 : 0

  subnet_id      = aws_subnet.transit_ha[0].id
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
  ha_subnet    = var.transit_gateway.ha_enabled ? aws_subnet.transit_ha[0].cidr_block : null
  ha_gw_size   = var.transit_gateway.ha_enabled ? "t3.small" : null

  local_as_number               = var.transit_gateway.asn
  enable_segmentation           = true
  enable_transit_firenet        = false
  connected_transit             = true
  enable_advertise_transit_cidr = true
  enable_active_standby         = false
  enable_gateway_load_balancer  = false
  enable_vpc_dns_server         = false
  enable_encrypt_volume         = true
  enable_preserve_as_path       = false
  enable_bgp_over_lan           = false

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

  enable_encrypt_volume = true
  enable_active_standby = false

  tags = merge(local.common_tags, {
    Environment = each.value.environment
  })

  # Explicit dependency on the route table association ensures the IGW route
  # exists before Aviatrix validates the subnet is public. Without this,
  # Aviatrix may see the subnet before the route table association is applied
  # and throw AVXERR-TRANSIT-0024 ("Gateways can only be launched in public subnets").
  depends_on = [aws_route_table_association.spokes_public]
}

# ============================================================================
# EC2 Instance Connect Endpoints (EICE)
# ============================================================================
# One endpoint per spoke VPC — allows SEs to SSH tunnel to private test VMs
# using only their existing AWS credentials. No public IPs, no key management,
# no IP whitelisting required. The `aws ec2-instance-connect ssh` command in
# the gatus_dashboards output auto-discovers these endpoints.
#
# One endpoint per spoke VPC — dev, prod, and db all get EICE so SEs can SSH in to test DCF policy enforcement from any VM.

# Security group for EC2 Instance Connect Endpoints.
# Allows outbound SSH (port 22) to the spoke VPC CIDR only.
resource "aws_security_group" "eice" {
  for_each = { for k, v in var.spokes : k => v }

  name_prefix = "${var.name_prefix}-${each.key}-eice-sg"
  description = "Security group for EC2 Instance Connect Endpoint in ${each.key} spoke"
  vpc_id      = aws_vpc.spokes[each.key].id

  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.spokes[each.key].cidr]
    description = "SSH to ${each.key} spoke VMs only"
  }

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-${each.key}-eice-sg"
    Environment = each.value.environment
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ec2_instance_connect_endpoint" "spokes" {
  for_each = { for k, v in var.spokes : k => v }

  subnet_id          = aws_subnet.spokes_public[each.key].id
  security_group_ids = [aws_security_group.eice[each.key].id]
  preserve_client_ip = false

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-${each.key}-eice"
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

  # DB SSH ingress from EICE security group is added via aws_security_group_rule below (same as dev/prod).

  # Allow ICMP (ping) from within the RFC1918 range for DCF policy testing
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "ICMP ping from private address space"
  }

  # Allow TCP 5432 (PostgreSQL) from private space — used for Gatus TCP probe demo
  # DCF enforces whether this traffic actually reaches the DB, regardless of SG allowance.
  dynamic "ingress" {
    for_each = each.key == "db" ? [1] : []
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]
      description = "PostgreSQL from private address space (DCF enforces policy)"
    }
  }

  # Allow SSH (22) from private address space for cross-spoke DCF policy testing.
  # DCF enforces whether this traffic actually reaches the DB, regardless of SG allowance.
  dynamic "ingress" {
    for_each = each.key == "db" ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]
      description = "SSH from private address space (DCF enforces policy)"
    }
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

  # Pin private IP so Gatus configs can reference it at plan time.
  # IP is the 10th host in the private /26 subnet for each spoke.
  private_ip = local.test_vm_ips[each.key]

  user_data = <<-SCRIPT
    #!/bin/bash
    yum update -y
    yum install -y tcpdump nmap
    hostnamectl set-hostname ${each.key}-test-vm
    echo "Welcome to ${each.key} test VM" > /etc/motd
    %{if each.key == "db"}
    # Persistent TCP listener on port 5432 — lets Gatus verify DCF permits
    # Prod -> DB TCP traffic end-to-end. Uses Python3 (pre-installed on AL2)
    # instead of nc/netcat which is not available in Amazon Linux 2 repos.
    cat > /etc/systemd/system/demo-db-listener.service <<EOF
[Unit]
Description=Demo DB port 5432 listener
After=network.target
[Service]
ExecStart=/usr/bin/python3 -c "import socket; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(('0.0.0.0',5432)); s.listen(10); [s.accept()[0].close() for _ in iter(int,1)]"
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable demo-db-listener
    systemctl start demo-db-listener
    %{endif}
    SCRIPT

  user_data_replace_on_change = true

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-${each.key}-test-vm"
    Environment = each.value.environment
    Role        = "test-instance"
  })
}

# SSH ingress from EICE security group for dev and prod test VMs.
# Uses aws_security_group_rule (not inline ingress) because source_security_group_id
# is not supported in inline ingress blocks.
resource "aws_security_group_rule" "test_vm_ssh_from_eice" {
  for_each = { for k, v in var.spokes : k => v }

  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eice[each.key].id
  security_group_id        = aws_security_group.test_vms[each.key].id
  description              = "SSH from EC2 Instance Connect Endpoint only"
}

# ============================================================================
# Spoke to Transit Attachments
# ============================================================================

resource "aviatrix_spoke_transit_attachment" "attachments" {
  for_each = var.spokes

  spoke_gw_name   = aviatrix_spoke_gateway.spokes[each.key].gw_name
  transit_gw_name = aviatrix_transit_gateway.main.gw_name
}
