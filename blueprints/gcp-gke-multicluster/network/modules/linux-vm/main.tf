terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

resource "google_compute_instance" "this" {
  project      = var.project_id
  name         = "${var.name_prefix}-db-vm"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
    }
  }

  network_interface {
    subnetwork = var.subnet_id
    # No access_config block → no external IP. Egress flows through the
    # Aviatrix spoke GW (default route from Aviatrix 9.0).
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -eux
    apt-get update
    apt-get install -y apache2
    echo "<h1>db.${var.dns_zone_name} — east-west test target</h1>" > /var/www/html/index.html
    systemctl enable --now apache2
  EOT

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  tags = ["aviatrix-db-vm"]
}
