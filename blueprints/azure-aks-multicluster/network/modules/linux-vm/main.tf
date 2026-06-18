locals {
  vm_name = "${var.name_prefix}-db-vm"
}

# SSH key pair — private key output for optional access
resource "tls_private_key" "vm" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_network_interface" "vm" {
  name                = "${local.vm_name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                = local.vm_name
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  tags                = merge(var.tags, { Name = local.vm_name, Role = "db-test" })

  network_interface_ids = [azurerm_network_interface.vm.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.vm.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Install nginx web server on boot — used as east-west test target.
  # The Aviatrix spoke GW SNAT may not be ready when cloud-init first runs,
  # so DNS / apt egress can fail for several minutes. Retry until they work.
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    until getent hosts archive.ubuntu.com >/dev/null; do sleep 30; done
    until apt-get update -y; do sleep 15; done
    until apt-get install -y nginx; do sleep 15; done
    systemctl enable nginx
    systemctl start nginx
    echo "<h1>DB Test VM: $(hostname)</h1><p>Private IP: $(hostname -I | awk '{print $1}')</p>" \
      > /var/www/html/index.html
  EOF
  )
}
