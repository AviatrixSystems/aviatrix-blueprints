# Bump triggers.deploy to force VM replacement (cloud-init re-runs, runner
# re-registers). The VM has replace_triggered_by pointing at this resource.
resource "null_resource" "runner_redeploy_trigger" {
  triggers = {
    deploy = "v3"
  }
}

locals {
  runner_name = local.name_prefix

  # owner/repo extracted from var.github_repo_url for GitHub API calls
  github_repo_slug = replace(var.github_repo_url, "https://github.com/", "")

  cloud_init = <<-EOT
    #!/bin/bash
    set -e

    # Create runner user
    useradd -m -s /bin/bash runner

    # Install dependencies
    apt-get update -y
    apt-get install -y curl jq tar

    # Fetch fresh registration token at boot via GitHub API (token valid 1h from creation)
    REG_TOKEN=$(curl -sf -X POST \
      -H "Authorization: Bearer ${var.github_pat}" \
      -H "Accept: application/vnd.github+json" \
      https://api.github.com/repos/${local.github_repo_slug}/actions/runners/registration-token \
      | jq -r .token)

    # Download runner v${var.runner_version}
    mkdir -p /home/runner/actions-runner
    cd /home/runner/actions-runner
    curl -o actions-runner-linux-x64-${var.runner_version}.tar.gz -L \
      https://github.com/actions/runner/releases/download/v${var.runner_version}/actions-runner-linux-x64-${var.runner_version}.tar.gz

    # Validate hash
    echo "${var.runner_package_hash}  actions-runner-linux-x64-${var.runner_version}.tar.gz" \
      | shasum -a 256 -c

    # Extract
    tar xzf ./actions-runner-linux-x64-${var.runner_version}.tar.gz

    # Configure (non-interactive); --replace removes any stale registration with same name
    chown -R runner:runner /home/runner/actions-runner
    su -c "./config.sh \
      --url ${var.github_repo_url} \
      --token $REG_TOKEN \
      --name ${local.runner_name} \
      --labels azure,self-hosted,linux,x64 \
      --replace \
      --unattended" runner

    # Install and start as systemd service
    ./svc.sh install runner
    ./svc.sh start
  EOT
}

resource "azurerm_network_security_group" "runner" {
  name                = "nsg-${local.name_prefix}"
  location            = azurerm_resource_group.runner.location
  resource_group_name = azurerm_resource_group.runner.name
  tags                = local.common_tags

  security_rule {
    name                       = "allow-rfc1918-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "runner" {
  name                = "nic-${local.name_prefix}"
  location            = azurerm_resource_group.runner.location
  resource_group_name = azurerm_resource_group.runner.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.runner.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "runner" {
  network_interface_id      = azurerm_network_interface.runner.id
  network_security_group_id = azurerm_network_security_group.runner.id
}

resource "azurerm_linux_virtual_machine" "runner" {
  name                            = "vm-${local.name_prefix}"
  computer_name                   = "vm-${local.name_prefix}"
  resource_group_name             = azurerm_resource_group.runner.name
  location                        = azurerm_resource_group.runner.location
  size                            = var.runner_vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  custom_data                     = base64encode(local.cloud_init)

  network_interface_ids = [
    azurerm_network_interface.runner.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  depends_on = [aviatrix_spoke_gateway.runner]

  lifecycle {
    replace_triggered_by = [null_resource.runner_redeploy_trigger]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  tags = merge(local.common_tags, {
    "gh-action" = "runner"
  })
}

# Publish the spoke gateway public IP to the GitHub repo as variable GW_PUBLIC_IP
# so the test-egress workflow can assert against it without calling the Aviatrix
# controller. Re-runs whenever the gateway IP changes.
#
# Uses the GitHub REST API directly via curl — no gh CLI dependency. The PAT
# (var.github_pat) needs `repo` scope; if the target repo is in a SAML-enforced
# org, the PAT must be SSO-authorized for that org first.
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

      # Try POST (create); if it 422s the variable already exists — PATCH it.
      http=$(curl -sS -o /tmp/_gw_resp.json -w '%%{http_code}' -X POST \
        -H "$${hdr_auth}" -H "$${hdr_accept}" "$${api}" \
        -d "{\"name\":\"GW_PUBLIC_IP\",\"value\":\"$${GW_IP}\"}")
      # GitHub returns 409 (conflict) when the variable already exists; older
      # docs sometimes show 422. Handle both, fall through to PATCH.
      if [ "$${http}" = "409" ] || [ "$${http}" = "422" ]; then
        http=$(curl -sS -o /tmp/_gw_resp.json -w '%%{http_code}' -X PATCH \
          -H "$${hdr_auth}" -H "$${hdr_accept}" "$${api}/GW_PUBLIC_IP" \
          -d "{\"value\":\"$${GW_IP}\"}")
      fi
      if [ "$${http}" != "201" ] && [ "$${http}" != "204" ]; then
        echo "ERROR: GitHub API returned $${http}" >&2
        cat /tmp/_gw_resp.json >&2
        exit 1
      fi
      echo "Published GW_PUBLIC_IP=$${GW_IP} to $${REPO}"
    EOT
  }
}

resource "null_resource" "runner_unregister" {
  triggers = {
    vm_id = azurerm_linux_virtual_machine.runner.id
    pat   = var.github_pat
    repo  = local.github_repo_slug
    name  = local.runner_name
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
