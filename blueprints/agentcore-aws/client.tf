# =============================================================================
# Client invoker EC2 - Amazon Linux 2023 ARM64 in the client spoke. Runs the
# probe script via SSM so no public key / SSH access is needed. The test
# harness (tests/probe.sh) exec's `aws bedrock-agentcore invoke-agent-runtime`
# from this instance - which routes through the transit, through the
# AgentCore spoke GW, out the PrivateLink endpoint, and back.
# =============================================================================

resource "aws_security_group" "client_invoker" {
  name        = "${local.name_prefix}-client-invoker"
  description = "Outbound-only. SSM-reachable. No inbound."
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

  user_data = <<-BASH
    #!/bin/bash
    set -euo pipefail
    dnf -y install awscli python3-pip python3-devel jq gcc
    # ---- containment-probe CLI (SSM-invocable) ---------------------------------
    cat > /usr/local/bin/probe-agentcore.sh <<'EOF'
    #!/bin/bash
    # Invoke the sample AgentCore runtime and pretty-print the probe results.
    set -euo pipefail
    RUNTIME_ARN="$${1:-$${AGENTCORE_RUNTIME_ARN:-}}"
    REGION="$${AWS_REGION:-us-east-2}"
    DATA_HOST="$${AGENTCORE_DATA_HOST:-bedrock-agentcore.$${REGION}.amazonaws.com}"
    if [[ -z "$${RUNTIME_ARN}" ]]; then
      echo "usage: probe-agentcore.sh <runtime-arn>" >&2
      exit 1
    fi
    echo "[probe] resolving $${DATA_HOST}"
    getent ahosts "$${DATA_HOST}" | head -1
    OUT=$(mktemp)
    PAYLOAD_B64=$(printf '%s' '{"task":"run-probes"}' | base64 -w0)
    SESSION="probe-$$(date +%s)-$$RANDOM-$$(head /dev/urandom | tr -dc a-f0-9 | head -c 16)"
    aws bedrock-agentcore invoke-agent-runtime \
      --region "$${REGION}" \
      --agent-runtime-arn "$${RUNTIME_ARN}" \
      --runtime-session-id "$${SESSION}" \
      --payload "$${PAYLOAD_B64}" \
      "$${OUT}" >/dev/null
    echo "[probe] runtime response:"
    cat "$${OUT}" | jq .
    EOF
    chmod +x /usr/local/bin/probe-agentcore.sh
    cat > /etc/profile.d/agentcore.sh <<'ENV'
    export AWS_REGION=${var.aws_region}
    ENV

    # ---- Streamlit scenario UI -------------------------------------------------
    # Fetch UI bundle from S3 (see ui.tf) so user_data stays under 16 KB.
    mkdir -p /opt/agentcore-ui
    UI_BUCKET='${aws_s3_bucket.ui.id}'
    aws s3 cp "s3://$${UI_BUCKET}/ui/app.py"            /opt/agentcore-ui/app.py
    aws s3 cp "s3://$${UI_BUCKET}/ui/scenarios.py"      /opt/agentcore-ui/scenarios.py
    aws s3 cp "s3://$${UI_BUCKET}/ui/scenarios.json"    /opt/agentcore-ui/scenarios.json
    aws s3 cp "s3://$${UI_BUCKET}/ui/requirements.txt"  /opt/agentcore-ui/requirements.txt
    aws s3 cp "s3://$${UI_BUCKET}/ui/agentcore-ui.service" /etc/systemd/system/agentcore-ui.service
    python3 -m venv /opt/agentcore-ui/venv
    /opt/agentcore-ui/venv/bin/pip install --upgrade pip >/dev/null
    /opt/agentcore-ui/venv/bin/pip install -r /opt/agentcore-ui/requirements.txt >/dev/null
    # Env file fields that depend on other terraform resources are
    # populated post-deploy via SSM (see ui-refresh.sh). On first boot
    # we leave placeholders; the service still starts and tells the
    # user what's missing.
    cat > /etc/agentcore-ui.env <<ENVEOF
AWS_REGION=${var.aws_region}
AGENTCORE_DATA_HOST=${local.agentcore_data_host}
AGENTCORE_RUNTIME_ARN=UNSET_POPULATED_POST_APPLY
AGENTCORE_RUNTIME_ROLE_ARN=UNSET_POPULATED_POST_APPLY
AGENTCORE_AGENT_IMAGE_URI=UNSET_POPULATED_POST_APPLY
ADVERSARY_MCP_URL=UNSET_POPULATED_POST_APPLY
ENVEOF
    systemctl daemon-reload
    systemctl enable --now agentcore-ui.service || true
  BASH

  tags = {
    Name = "${local.name_prefix}-client-invoker"
  }

  depends_on = [module.spoke_client]
}
