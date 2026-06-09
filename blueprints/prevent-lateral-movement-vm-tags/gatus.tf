# ============================================================================
# Gatus - Prevent Lateral Movement Live Dashboard
#
# Deploys a Gatus instance in the prod spoke VPC to visually reflect
# segmentation policy outcomes (allowed vs denied traffic).
# Exposed via an internet-facing ALB — no SSH or SSM required.
#
# SE usage: after `terraform apply`, open the `gatus_dashboard_url` output
# in a browser. No local tooling dependencies.
#
# IMPORTANT - DCF SmartGroup classification:
# This instance is tagged Environment = "production" so it is classified into
# the prod SmartGroup. This allows the allow-prod-to-db policy (priority 100)
# to apply — Gatus probes originate from "prod" and can reach "db", producing
# the GREEN tile in the dashboard. Do not change this tag or the probe results
# will not reflect the intended DCF policy outcomes.
# ============================================================================

locals {
  # Pin private IPs for test VMs so they can be referenced at plan time.
  # Uses host 10 in each spoke's private /26 subnet to avoid conflicts
  # with DHCP at the start of the range.
  #
  # Default values (with default spokes variable):
  #   dev  = 10.1.0.74  (cidrhost("10.1.0.64/26", 10))
  #   prod = 10.2.0.74  (cidrhost("10.2.0.64/26", 10))
  #   db   = 10.3.0.74  (cidrhost("10.3.0.64/26", 10))
  test_vm_ips = {
    for k, v in var.spokes : k => cidrhost(cidrsubnet(v.cidr, 2, 1), 10)
  }
}

# ----------------------------------------------------------------------------
# Second public subnet in prod VPC (required for ALB multi-AZ)
# ----------------------------------------------------------------------------

resource "aws_subnet" "gatus_alb_subnet" {
  vpc_id                  = aws_vpc.spokes["prod"].id
  cidr_block              = cidrsubnet(var.spokes["prod"].cidr, 2, 2)
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-gatus-alb-subnet"
    Environment = "monitoring"
  })
}

resource "aws_route_table_association" "gatus_alb_subnet" {
  subnet_id      = aws_subnet.gatus_alb_subnet.id
  route_table_id = aws_route_table.spokes_public["prod"].id
}

# ----------------------------------------------------------------------------
# Security Groups
# ----------------------------------------------------------------------------

resource "aws_security_group" "gatus_alb" {
  name_prefix = "${var.name_prefix}-gatus-alb-sg"
  description = "Allows HTTP access to the Gatus dashboard ALB"
  vpc_id      = aws_vpc.spokes["prod"].id

  ingress {
    description = "HTTP to Gatus dashboard"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.gatus_allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-gatus-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "gatus" {
  name_prefix = "${var.name_prefix}-gatus-sg"
  description = "Allows ALB to reach Gatus on port 8080"
  vpc_id      = aws_vpc.spokes["prod"].id

  ingress {
    description     = "Gatus UI from ALB only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.gatus_alb.id]
  }

  egress {
    description = "Allow all outbound (Gatus needs to reach test VMs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-gatus-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ----------------------------------------------------------------------------
# Gatus EC2 Instance
# Placed in the prod public subnet so it can route to other spoke VMs
# via the Aviatrix transit gateway.
# ----------------------------------------------------------------------------

resource "aws_instance" "gatus" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.test_vm_instance_type
  key_name                    = var.test_vm_key_name
  subnet_id                   = aws_subnet.spokes_public["prod"].id
  vpc_security_group_ids      = [aws_security_group.gatus.id]
  associate_public_ip_address = true # needs outbound internet to pull Docker image; inbound still restricted to ALB via SG

  user_data = base64encode(templatefile("${path.module}/gatus_config.tftpl", {
    dev_ip  = aws_instance.test_vms["dev"].private_ip
    prod_ip = aws_instance.test_vms["prod"].private_ip
    db_ip   = aws_instance.test_vms["db"].private_ip
  }))

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-gatus"
    Environment = "production"
    Role        = "gatus-monitor"
  })

  depends_on = [aws_instance.test_vms]
}

# ----------------------------------------------------------------------------
# Application Load Balancer
# ----------------------------------------------------------------------------

resource "aws_lb" "gatus" {
  name               = "${var.name_prefix}-gatus-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.gatus_alb.id]

  subnets = [
    aws_subnet.spokes_public["prod"].id,
    aws_subnet.gatus_alb_subnet.id
  ]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-gatus-alb"
  })
}

resource "aws_lb_target_group" "gatus" {
  name        = "${var.name_prefix}-gatus-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.spokes["prod"].id
  target_type = "instance"

  health_check {
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-gatus-tg"
  })
}

resource "aws_lb_target_group_attachment" "gatus" {
  target_group_arn = aws_lb_target_group.gatus.arn
  target_id        = aws_instance.gatus.id
  port             = 8080
}

resource "aws_lb_listener" "gatus" {
  load_balancer_arn = aws_lb.gatus.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gatus.arn
  }
}
