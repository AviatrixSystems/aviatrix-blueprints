# Bump triggers.deploy to force EC2 replacement (user_data re-runs, runner
# re-registers). The EC2 has replace_triggered_by pointing at this resource.
resource "null_resource" "runner_redeploy_trigger" {
  triggers = {
    deploy = "v1"
  }
}

locals {
  runner_name = local.name_prefix

  # owner/repo extracted from var.github_repo_url for GitHub API calls
  github_repo_slug = replace(var.github_repo_url, "https://github.com/", "")

  user_data = <<-EOT
    #!/bin/bash
    set -e

    useradd -m -s /bin/bash runner

    apt-get update -y
    apt-get install -y curl jq tar

    # Fetch fresh registration token at boot via GitHub API (token valid 1h from creation)
    REG_TOKEN=$(curl -sf -X POST \
      -H "Authorization: Bearer ${var.github_pat}" \
      -H "Accept: application/vnd.github+json" \
      https://api.github.com/repos/${local.github_repo_slug}/actions/runners/registration-token \
      | jq -r .token)

    mkdir -p /home/runner/actions-runner
    cd /home/runner/actions-runner
    curl -o actions-runner-linux-x64-${var.runner_version}.tar.gz -L \
      https://github.com/actions/runner/releases/download/v${var.runner_version}/actions-runner-linux-x64-${var.runner_version}.tar.gz

    echo "${var.runner_package_hash}  actions-runner-linux-x64-${var.runner_version}.tar.gz" \
      | shasum -a 256 -c

    tar xzf ./actions-runner-linux-x64-${var.runner_version}.tar.gz

    chown -R runner:runner /home/runner/actions-runner
    su -c "./config.sh \
      --url ${var.github_repo_url} \
      --token $REG_TOKEN \
      --name ${local.runner_name} \
      --labels aws,self-hosted,linux,x64 \
      --replace \
      --unattended" runner

    ./svc.sh install runner
    ./svc.sh start
  EOT
}

resource "aws_security_group" "runner" {
  name        = "${local.name_prefix}-sg"
  description = "Runner VM security group: inbound restricted to the VPC, egress unrestricted (DCF on the spoke GW enforces FQDN allow-list)."
  vpc_id      = aws_vpc.runner.id

  ingress {
    description = "Allow all inbound from within the VPC (parity with Azure NSG allow-rfc1918-inbound)."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound; the DCF ruleset on the Aviatrix spoke gateway enforces the FQDN allow-list."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sg"
  })
}

resource "aws_instance" "runner" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.runner_instance_type
  subnet_id                   = aws_subnet.runner.id
  vpc_security_group_ids      = [aws_security_group.runner.id]
  key_name                    = var.aws_key_pair_name
  user_data                   = local.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  depends_on = [aviatrix_spoke_gateway.runner]

  lifecycle {
    replace_triggered_by = [null_resource.runner_redeploy_trigger]
  }

  tags = merge(local.common_tags, {
    Name        = "ec2-${local.name_prefix}"
    "gh-action" = "runner"
  })
}

# Publish the spoke gateway public IP to the GitHub repo as variable GW_PUBLIC_IP
# so the test-egress workflow can assert against it without calling the Aviatrix
# controller. Re-runs whenever the gateway IP changes.
#
# Uses the GitHub REST API directly via curl. The PAT (var.github_pat) needs
# `repo` scope; if the target repo is in a SAML-enforced org, the PAT must be
# SSO-authorized for that org first.
resource "null_resource" "publish_gw_ip" {
  triggers = {
    gw_ip = aviatrix_spoke_gateway.runner.public_ip
    repo  = local.github_repo_slug
    pat   = var.github_pat
  }

  provisioner "local-exec" {
    environment = {
      PAT   = self.triggers.pat
      REPO  = self.triggers.repo
      GW_IP = self.triggers.gw_ip
    }
    command = <<-EOT
      set -e
      api="https://api.github.com/repos/$${REPO}/actions/variables"
      hdr_auth="Authorization: Bearer $${PAT}"
      hdr_accept="Accept: application/vnd.github+json"

      http=$(curl -sS -o /tmp/_gw_resp.json -w '%%{http_code}' -X POST \
        -H "$${hdr_auth}" -H "$${hdr_accept}" "$${api}" \
        -d "{\"name\":\"GW_PUBLIC_IP_AWS\",\"value\":\"$${GW_IP}\"}")
      # GitHub returns 409 (conflict) when the variable already exists; older
      # docs sometimes show 422. Handle both, fall through to PATCH.
      if [ "$${http}" = "409" ] || [ "$${http}" = "422" ]; then
        http=$(curl -sS -o /tmp/_gw_resp.json -w '%%{http_code}' -X PATCH \
          -H "$${hdr_auth}" -H "$${hdr_accept}" "$${api}/GW_PUBLIC_IP_AWS" \
          -d "{\"value\":\"$${GW_IP}\"}")
      fi
      if [ "$${http}" != "201" ] && [ "$${http}" != "204" ]; then
        echo "ERROR: GitHub API returned $${http}" >&2
        cat /tmp/_gw_resp.json >&2
        exit 1
      fi
      echo "Published GW_PUBLIC_IP_AWS=$${GW_IP} to $${REPO}"
    EOT
  }
}

resource "null_resource" "runner_unregister" {
  triggers = {
    instance_id = aws_instance.runner.id
    pat         = var.github_pat
    repo        = local.github_repo_slug
    name        = local.runner_name
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      RUNNER_ID=$(curl -sf \
        -H "Authorization: Bearer ${self.triggers.pat}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${self.triggers.repo}/actions/runners" \
        | jq -r --arg name "${self.triggers.name}" '.runners[] | select(.name == $name) | .id')
      if [ -n "$RUNNER_ID" ] && [ "$RUNNER_ID" != "null" ]; then
        curl -sf -X DELETE \
          -H "Authorization: Bearer ${self.triggers.pat}" \
          -H "Accept: application/vnd.github+json" \
          "https://api.github.com/repos/${self.triggers.repo}/actions/runners/$RUNNER_ID"
        echo "Runner force-removed (ID: $RUNNER_ID)"
      else
        echo "Runner not found or already removed, skipping"
      fi
    EOT
  }
}
