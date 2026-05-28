# =============================================================================
# Client invoker EC2 - Amazon Linux 2023 ARM64 in the client spoke. Hosts the
# AgentCore VCA UI (FastAPI/Streamlit) behind the public ALB. The UI service
# drives the AgentCore runtime via `aws bedrock-agentcore invoke-agent-runtime`,
# which routes through the transit, through the AgentCore spoke GW, out the
# PrivateLink endpoint, and back.
# =============================================================================

resource "aws_security_group" "client_invoker" {
  name        = "${local.name_prefix}-client-invoker"
  description = "Outbound-only. ALB ingress on 8501 only. No SSH."
  vpc_id      = aws_vpc.client.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-client-invoker-sg"
  }
}

resource "aws_instance" "client_invoker" {
  ami                  = data.aws_ami.al2023_arm64.id
  instance_type        = "t4g.small"
  subnet_id            = aws_subnet.client_workload.id
  iam_instance_profile = aws_iam_instance_profile.client_invoker.name

  vpc_security_group_ids = [aws_security_group.client_invoker.id]

  metadata_options {
    http_tokens = "required"
  }

  # Outer heredoc is NOT indented (no <<-). The inner ENVEOF body must be at
  # column 0 so bash matches its terminator, which means the minimum indent
  # across the user_data is 0. Keep everything flat at column 0 so cloud-init
  # accepts the shebang.
  user_data = <<BASH
#!/bin/bash
set -euo pipefail
dnf -y install awscli python3-pip python3-devel jq

# ---- AgentCore VCA AI Attack Simulation UI (FastAPI) ----------------------
# Bucket prefix "ui/" maps to /opt/agentcore-ui/ via recursive cp — pulls the
# python package, templates, static assets, scenarios.json, rules.json,
# requirements.txt, and the systemd unit.
mkdir -p /opt/agentcore-ui
UI_BUCKET='${aws_s3_bucket.ui.id}'
aws s3 cp --recursive "s3://$${UI_BUCKET}/ui/" /opt/agentcore-ui/
mv /opt/agentcore-ui/agentcore-ui.service /etc/systemd/system/agentcore-ui.service

python3 -m venv /opt/agentcore-ui/venv
/opt/agentcore-ui/venv/bin/pip install --upgrade pip >/dev/null
/opt/agentcore-ui/venv/bin/pip install -r /opt/agentcore-ui/requirements.txt >/dev/null

# Env vars dependent on resources outside this instance's apply graph are
# placeholders here; populated post-apply via SSM. The service still starts
# and surfaces a "config pending" state via /api/run/*.
cat > /etc/agentcore-ui.env <<ENVEOF
AWS_REGION=${var.aws_region}
AGENTCORE_DATA_HOST=${local.agentcore_data_host}
AGENTCORE_RUNTIME_ARN=UNSET_POPULATED_POST_APPLY
AGENTCORE_RUNTIME_ROLE_ARN=UNSET_POPULATED_POST_APPLY
AGENTCORE_AGENT_IMAGE_URI=UNSET_POPULATED_POST_APPLY
ADVERSARY_MCP_URL=UNSET_POPULATED_POST_APPLY
AVIATRIX_CONTROLLER_VERSION=9.0.10
AVIATRIX_COPILOT_URL=${local.copilot_dcf_url}
ENVEOF
systemctl daemon-reload
systemctl enable --now agentcore-ui.service || true
BASH

  tags = {
    Name = "${local.name_prefix}-client-invoker"
  }

  depends_on = [module.spoke_client]
}
