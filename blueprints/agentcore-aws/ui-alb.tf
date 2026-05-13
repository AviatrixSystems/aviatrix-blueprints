# =============================================================================
# UI Application Load Balancer
#
# Browser access to the Streamlit scenario UI without standing up an
# EC2 Instance Connect tunnel. SG-level IP allowlist (var.ui_ingress_cidrs)
# is the only ingress gate; the ALB publishes a public DNS name with no
# auth layer beyond the network ACL. This matches "private demo lab"
# threat posture - for production, put Cognito / OIDC in front via ALB
# listener rules or front with API Gateway + JWT.
#
# ALB requires two AZs; we reuse the existing client-gw subnet in AZ[0]
# and the new client-alb-b subnet in AZ[1].
# =============================================================================

resource "aws_security_group" "ui_alb" {
  name        = "${local.name_prefix}-ui-alb"
  description = "Ingress for Streamlit UI ALB - IP-allowlisted"
  vpc_id      = aws_vpc.client.id

  ingress {
    description = "HTTP from allowlisted operator CIDRs"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.ui_ingress_cidrs
  }

  egress {
    description = "Forward to Streamlit targets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.client_spoke_cidr]
  }

  tags = {
    Name = "${local.name_prefix}-ui-alb-sg"
  }
}

# Allow the ALB to reach the Streamlit port on the invoker EC2.
resource "aws_security_group_rule" "client_invoker_alb_ui" {
  type                     = "ingress"
  from_port                = 8501
  to_port                  = 8501
  protocol                 = "tcp"
  security_group_id        = aws_security_group.client_invoker.id
  source_security_group_id = aws_security_group.ui_alb.id
  description              = "ALB to Streamlit UI"
}

resource "aws_lb" "ui" {
  name               = "${local.name_prefix}-ui"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.ui_alb.id]
  subnets            = [aws_subnet.client_gw.id, aws_subnet.client_alb_b.id]

  # Streamlit uses WebSockets for its stream channel; ALB supports WS
  # natively on HTTP/1.1 upgrade. Default idle_timeout = 60s is tight
  # for long-running scenarios (cold-start sessions); bump to 300s.
  idle_timeout = 300

  drop_invalid_header_fields = true
  enable_deletion_protection = false

  tags = {
    Name = "${local.name_prefix}-ui"
  }
}

resource "aws_lb_target_group" "ui" {
  name        = "${local.name_prefix}-ui-tg"
  port        = 8501
  protocol    = "HTTP"
  vpc_id      = aws_vpc.client.id
  target_type = "instance"

  # Streamlit exposes a health endpoint at /_stcore/health (200 when ready).
  health_check {
    path                = "/_stcore/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # Streamlit holds a WebSocket per client and all state is server-side;
  # stickiness guarantees the same client hits the same target on reconnect.
  # With a single target it's a belt-and-braces setting.
  stickiness {
    enabled         = true
    type            = "lb_cookie"
    cookie_duration = 3600
  }

  tags = {
    Name = "${local.name_prefix}-ui-tg"
  }
}

resource "aws_lb_target_group_attachment" "ui" {
  target_group_arn = aws_lb_target_group.ui.arn
  target_id        = aws_instance.client_invoker.id
  port             = 8501
}

resource "aws_lb_listener" "ui_http" {
  load_balancer_arn = aws_lb.ui.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ui.arn
  }

  tags = {
    Name = "${local.name_prefix}-ui-http"
  }
}
