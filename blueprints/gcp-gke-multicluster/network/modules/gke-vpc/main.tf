terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# Custom-mode VPC: subnets are explicit, no auto-created subnets.
resource "google_compute_network" "this" {
  name                            = "${var.name_prefix}-${var.name}-vpc"
  project                         = var.project_id
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = false
}

# Node subnet — primary range for nodes, secondary ranges for pods and services.
# Aliasing the secondary ranges into the subnet is GKE's VPC-native (alias IP) requirement.
resource "google_compute_subnetwork" "nodes" {
  name          = "${var.name_prefix}-${var.name}-nodes"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = var.nodes_cidr

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  private_ip_google_access = true
}

# Aviatrix spoke GW subnet — small dedicated /28 in the GW's zone region.
resource "google_compute_subnetwork" "avx_gw" {
  name                     = "${var.name_prefix}-${var.name}-avx-gw"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.avx_gw_cidr
  private_ip_google_access = true
}

# Required by GCP Standard ALB (Gateway API) — each region needs at most one
# proxy-only subnet shared by all L7 LBs in the region. Reserve here so the
# nodes layer can request a Gateway without a chicken-and-egg ordering problem.
resource "google_compute_subnetwork" "proxy_only" {
  count         = var.create_proxy_only_subnet ? 1 : 0
  name          = "${var.name_prefix}-${var.name}-proxy-only"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = var.proxy_only_cidr
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# Allow internal traffic within the VPC, from the GKE master CIDR, and from
# any other Aviatrix-attached spoke (post-SNAT, traffic arrives with a source
# from the other spoke's GW subnet — also RFC1918). Without 10/8 + 192.168/16
# + 172.16/12 in source_ranges, east-west between spokes is silently dropped
# at the destination VPC even though the Aviatrix DCF rule permits it.
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.name_prefix}-${var.name}-allow-internal"
  project = var.project_id
  network = google_compute_network.this.name

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_ranges = concat(
    ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"],
    [var.pods_cidr, var.services_cidr],
    var.master_ipv4_cidr_block != null ? [var.master_ipv4_cidr_block] : [],
  )
}

# Allow Google's health-check + LB infrastructure to probe pods/nodes.
# https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges
resource "google_compute_firewall" "allow_health_checks" {
  name    = "${var.name_prefix}-${var.name}-allow-hc"
  project = var.project_id
  network = google_compute_network.this.name

  allow {
    protocol = "tcp"
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
}
