# =============================================================================
# EC2 Instance Connect Endpoint (EICE) - lets operators port-forward to the
# client invoker without installing the Session Manager plugin on their Mac.
#
# Usage from a Mac with only the AWS CLI:
#
#   aws ec2-instance-connect open-tunnel \
#     --region us-east-2 \
#     --instance-id $(terraform output -raw client_invoker_instance_id) \
#     --remote-port 8501 \
#     --local-port 8501
#
# Then browse to http://localhost:8501 for the probe UI.
#
# EICE itself is free; you are only billed for data through the tunnel.
# =============================================================================

resource "aws_security_group" "eice" {
  name        = "${local.name_prefix}-eice"
  description = "EC2 Instance Connect Endpoint - outbound to workloads in the client spoke"
  vpc_id      = aws_vpc.client.id

  egress {
    description = "Tunnel traffic to workloads in the client spoke CIDR"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.client_spoke_cidr]
  }

  tags = {
    Name = "${local.name_prefix}-eice-sg"
  }
}

resource "aws_ec2_instance_connect_endpoint" "client" {
  subnet_id          = aws_subnet.client_workload.id
  security_group_ids = [aws_security_group.eice.id]
  # PreserveClientIp is a control-plane flag; leaving default (true) is fine.

  tags = {
    Name = "${local.name_prefix}-eice"
  }
}

# Allow the EICE to reach the invoker EC2 on the Streamlit port + SSH.
# Ingress is scoped to the EICE security group so nothing else in the VPC
# can hit these ports.
resource "aws_security_group_rule" "client_invoker_eice_ui" {
  type                     = "ingress"
  from_port                = 8501
  to_port                  = 8501
  protocol                 = "tcp"
  security_group_id        = aws_security_group.client_invoker.id
  source_security_group_id = aws_security_group.eice.id
  description              = "EICE tunnel to Streamlit UI"
}

resource "aws_security_group_rule" "client_invoker_eice_ssh" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.client_invoker.id
  source_security_group_id = aws_security_group.eice.id
  description              = "EICE tunnel to SSH (optional diag)"
}
