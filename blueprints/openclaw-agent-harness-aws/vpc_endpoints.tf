# =============================================================================
# Private AWS management endpoints
# =============================================================================
# These endpoints make the SSM-only access path reliable without depending on an
# already-tuned Internet egress allow-list. They also reduce the amount of AWS
# control-plane traffic that needs to leave the VPC through public endpoints.

resource "aws_security_group" "vpc_endpoints" {
  count       = var.create_ssm_vpc_endpoints ? 1 : 0
  name        = "${local.name}-vpc-endpoints"
  description = "Interface endpoint security group for private agent management traffic."
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from private agent subnet(s)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.private_subnet_cidrs
  }

  egress {
    description = "Endpoint return traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-vpc-endpoints-sg"
  })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.create_ssm_vpc_endpoints ? local.ssm_interface_endpoint_services : toset([])

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.agent_private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-${each.key}-endpoint"
  })
}

resource "aws_vpc_endpoint" "s3" {
  count             = var.create_s3_gateway_endpoint ? 1 : 0
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.agent_private.id]

  tags = merge(local.common_tags, {
    Name = "${local.name}-s3-endpoint"
  })
}
