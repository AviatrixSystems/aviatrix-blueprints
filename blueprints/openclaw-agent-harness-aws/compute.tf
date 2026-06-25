# =============================================================================
# Private OpenClaw / NemoClaw terminal VM
# =============================================================================
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "agent" {
  name        = "${local.name}-agent"
  description = "Private OpenClaw terminal host. No inbound access; egress controlled by Aviatrix DCF."
  vpc_id      = aws_vpc.this.id

  # No ingress. Use AWS Systems Manager Session Manager.

  egress {
    description = "All egress reaches the Aviatrix Spoke Gateway path; DCF performs allow/deny."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-agent-sg"
  })
}

resource "aws_instance" "agent" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.agent_instance_type
  subnet_id                   = aws_subnet.agent_private[0].id
  private_ip                  = var.agent_private_ip == "" ? null : var.agent_private_ip
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.agent.name
  vpc_security_group_ids      = [aws_security_group.agent.id]

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/user_data_openclaw.sh.tftpl", {
    name_prefix                      = local.name
    install_mode                     = var.install_mode
    auto_run_installer               = var.auto_run_installer ? "true" : "false"
    auto_accept_third_party_software = var.auto_accept_third_party_software ? "true" : "false"
    install_docker                   = var.install_docker ? "true" : "false"
    install_bootstrap_packages       = var.install_bootstrap_packages ? "true" : "false"
  })

  root_block_device {
    volume_size           = var.agent_root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-agent-vm"
    }, {
    # Workload-identity tag the agent SmartGroup matches on (default Role=openclaw-agent-harness).
    (var.agent_workload_tag_key) = var.agent_workload_tag_value
  })

  depends_on = [
    module.spoke,
    aws_vpc_endpoint.interface,
    aws_vpc_endpoint.s3
  ]
}
