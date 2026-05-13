# =============================================================================
# Interface VPC endpoints for the AgentCore data plane and control plane.
#
# private_dns_enabled = false. We own the DNS via a shared Route 53 Private
# Hosted Zone (see route53.tf) so both the AgentCore spoke and the client
# spoke resolve the regional hostname to the endpoint IP. AWS's per-endpoint
# auto-created private DNS is scoped to a single VPC, which we don't want.
#
# Endpoint policy left open ("*") since:
#   - For data-plane OAuth-JWT inbound (per AWS docs), the policy Principal
#     must be "*" because VPC endpoint policies key on IAM principals, not
#     OAuth subjects.
#   - Network-layer containment is enforced by DCF, not by endpoint policy.
# =============================================================================

# Security group for the interface endpoints. Only 443/TCP from within
# our VPC fabric (the spoke gateway will SNAT client-spoke traffic through
# its ENI before it hits the endpoint).
resource "aws_security_group" "privatelink" {
  name        = "${local.name_prefix}-privatelink"
  description = "Ingress to AgentCore PrivateLink endpoints"
  vpc_id      = aws_vpc.agentcore.id

  ingress {
    description = "HTTPS from Aviatrix fabric and AgentCore spoke"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [
      var.agentcore_spoke_cidr,
      var.client_spoke_cidr,
      var.transit_cidr,
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-privatelink-sg"
  }
}

resource "aws_vpc_endpoint" "agentcore_data" {
  vpc_id              = aws_vpc.agentcore.id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-agentcore"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.agentcore_endpoint.id]
  security_group_ids  = [aws_security_group.privatelink.id]
  private_dns_enabled = false

  tags = {
    Name = "${local.name_prefix}-pl-agentcore-data"
    Role = "agentcore-privatelink-data"
  }
}

resource "aws_vpc_endpoint" "agentcore_control" {
  vpc_id              = aws_vpc.agentcore.id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-agentcore-control"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.agentcore_endpoint.id]
  security_group_ids  = [aws_security_group.privatelink.id]
  private_dns_enabled = false

  tags = {
    Name = "${local.name_prefix}-pl-agentcore-control"
    Role = "agentcore-privatelink-control"
  }
}
