provider "aviatrix" {
  controller_ip           = var.aviatrix_controller_ip
  username                = var.aviatrix_username
  password                = var.aviatrix_password
  skip_version_validation = true
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

#####################
# Project APIs
#
# Enable required GCP services up front so downstream layers (clusters/, etc.)
# don't fail with "API has not been used in project ... before or it is
# disabled". `disable_on_destroy = false` keeps these on after destroy — they
# may be shared with other workloads in the project.
#####################

resource "google_project_service" "required" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
  ])
  project            = var.gcp_project_id
  service            = each.key
  disable_on_destroy = false
}

locals {
  clusters = {
    frontend = {
      name     = "${var.name_prefix}-frontend"
      vpc_cidr = var.frontend_vpc_cidr
    }
    backend = {
      name     = "${var.name_prefix}-backend"
      vpc_cidr = var.backend_vpc_cidr
    }
  }

  common_labels = {
    environment = "demo"
    terraform   = "true"
    blueprint   = "gcp-gke-multicluster"
  }

  # GKE self_link cluster_id, constructed locally so the network layer can build
  # K8s-typed SmartGroups before the clusters layer runs. Format must match
  # google_container_cluster.this.self_link in clusters/* — for ZONAL clusters
  # the path is `/zones/<zone>/`, for REGIONAL it is `/locations/<region>/`.
  # This blueprint uses zonal clusters; flip if you change the cluster scope.
  frontend_cluster_id = "https://container.googleapis.com/v1/projects/${var.gcp_project_id}/zones/${var.gcp_zone}/clusters/${local.clusters.frontend.name}"
  backend_cluster_id  = "https://container.googleapis.com/v1/projects/${var.gcp_project_id}/zones/${var.gcp_zone}/clusters/${local.clusters.backend.name}"

  # The Aviatrix mc-* modules want a region (e.g., "us-central1") and build the
  # zone internally as "${region}-${az1}". Pass the AZ letter extracted from
  # gcp_zone so the gateway lands in the same zone as the GKE clusters/DB VM.
  gcp_az = trimprefix(var.gcp_zone, "${var.gcp_region}-")
}

#####################
# Aviatrix Transit Gateway
#
# In GCP the gateway is zonal (vpc_reg expects a zone, not a region). We pass
# the user's chosen zone to mc-transit; the Aviatrix-managed transit VPC's
# subnet is created in that zone's region implicitly by the controller.
#####################

module "gcp_transit" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "~> 8.0"

  name    = "${var.name_prefix}-transit"
  cloud   = "GCP"
  account = var.aviatrix_gcp_account_name
  region  = var.gcp_region
  az1     = local.gcp_az
  cidr    = var.transit_cidr
  ha_gw   = false

  instance_size = var.gw_instance_size

  # Non-overlapping pod CIDRs: frontend uses 100.64.0.0/17, backend
  # 100.64.128.0/17. Both are non-RFC1918 CGNAT space; we exclude the parent
  # /16 from BGP advertisements so non-pod traffic doesn't pull these into
  # peer routing tables.
  excluded_advertised_spoke_routes = "100.64.0.0/16"
}

#####################
# Frontend VPC + Spoke Gateway
#####################

module "frontend_vpc" {
  source = "./modules/gke-vpc"

  name                     = "frontend"
  name_prefix              = var.name_prefix
  project_id               = var.gcp_project_id
  region                   = var.gcp_region
  vpc_cidr                 = var.frontend_vpc_cidr
  nodes_cidr               = var.frontend_nodes_cidr
  pods_cidr                = var.frontend_pods_cidr
  services_cidr            = var.services_cidr
  avx_gw_cidr              = var.frontend_avx_gw_cidr
  master_ipv4_cidr_block   = var.frontend_master_cidr
  create_proxy_only_subnet = true
  proxy_only_cidr          = var.frontend_proxy_only_cidr
}

module "frontend_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  cloud      = "GCP"
  name       = "${var.name_prefix}-frontend-spoke"
  account    = var.aviatrix_gcp_account_name
  region     = var.gcp_region
  az1        = local.gcp_az
  transit_gw = module.gcp_transit.transit_gateway.gw_name

  instance_size = var.gw_instance_size
  ha_gw         = false

  # Bring the existing GCP VPC created by gke-vpc.
  use_existing_vpc = true
  vpc_id           = module.frontend_vpc.aviatrix_vpc_id
  gw_subnet        = module.frontend_vpc.avx_gw_subnet_cidr
}

# Customized SNAT mirrors aws-eks-multicluster — pod CIDR (transit + eth0)
# plus node subnet (eth0). On GCP this hits a controller bug:
# validate_dst_cidr rejects pod-CIDR src because gw_obj.vpc_cidr does not
# enumerate subnet secondaryIpRanges, so the 991 route → spoke-GW is never
# programmed. Workaround: program the route manually via gcloud (untagged,
# priority 991). Tracked in AVX bug ticket; see GCP_GKE_MULTICLUSTER_SNAT_GAP.md.
resource "aviatrix_gateway_snat" "frontend_spoke_snat" {
  gw_name   = module.frontend_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  # Pod CIDR → all destinations via transit
  snat_policy {
    src_cidr   = var.frontend_pods_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.gcp_transit.transit_gateway.gw_name
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  # Pod CIDR → internet via eth0
  snat_policy {
    src_cidr   = var.frontend_pods_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  # GKE node subnet → internet via eth0
  snat_policy {
    src_cidr   = var.frontend_nodes_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.frontend_spoke]
}

#####################
# Backend VPC + Spoke Gateway
#####################

module "backend_vpc" {
  source = "./modules/gke-vpc"

  name                     = "backend"
  name_prefix              = var.name_prefix
  project_id               = var.gcp_project_id
  region                   = var.gcp_region
  vpc_cidr                 = var.backend_vpc_cidr
  nodes_cidr               = var.backend_nodes_cidr
  pods_cidr                = var.backend_pods_cidr
  services_cidr            = var.services_cidr
  avx_gw_cidr              = var.backend_avx_gw_cidr
  master_ipv4_cidr_block   = var.backend_master_cidr
  create_proxy_only_subnet = true
  proxy_only_cidr          = var.backend_proxy_only_cidr
}

module "backend_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  cloud      = "GCP"
  name       = "${var.name_prefix}-backend-spoke"
  account    = var.aviatrix_gcp_account_name
  region     = var.gcp_region
  az1        = local.gcp_az
  transit_gw = module.gcp_transit.transit_gateway.gw_name

  instance_size = var.gw_instance_size
  ha_gw         = false

  use_existing_vpc = true
  vpc_id           = module.backend_vpc.aviatrix_vpc_id
  gw_subnet        = module.backend_vpc.avx_gw_subnet_cidr
}

resource "aviatrix_gateway_snat" "backend_spoke_snat" {
  gw_name   = module.backend_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  snat_policy {
    src_cidr   = var.backend_pods_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.gcp_transit.transit_gateway.gw_name
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = var.backend_pods_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = var.backend_nodes_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.backend_spoke]
}

#####################
# DB Spoke (test VM for east-west traffic demo)
#####################

resource "google_compute_network" "db" {
  name                    = "${var.name_prefix}-db-vpc"
  project                 = var.gcp_project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "db_vms" {
  name                     = "${var.name_prefix}-db-vms"
  project                  = var.gcp_project_id
  region                   = var.gcp_region
  network                  = google_compute_network.db.id
  ip_cidr_range            = var.db_subnet_cidr
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "db_avx_gw" {
  name                     = "${var.name_prefix}-db-avx-gw"
  project                  = var.gcp_project_id
  region                   = var.gcp_region
  network                  = google_compute_network.db.id
  ip_cidr_range            = var.db_avx_gw_cidr
  private_ip_google_access = true
}

resource "google_compute_firewall" "db_internal" {
  name    = "${var.name_prefix}-db-allow-internal"
  project = var.gcp_project_id
  network = google_compute_network.db.name

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  # Allow traffic from any spoke that's reachable through transit (RFC1918).
  source_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

module "db_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  cloud      = "GCP"
  name       = "${var.name_prefix}-db-spoke"
  account    = var.aviatrix_gcp_account_name
  region     = var.gcp_region
  az1        = local.gcp_az
  transit_gw = module.gcp_transit.transit_gateway.gw_name

  instance_size = var.gw_instance_size
  ha_gw         = false

  use_existing_vpc = true
  vpc_id           = "${google_compute_network.db.name}~-~${var.gcp_project_id}"
  gw_subnet        = google_compute_subnetwork.db_avx_gw.ip_cidr_range

  single_ip_snat = true
}

module "db_vm" {
  source = "./modules/linux-vm"

  name_prefix   = var.name_prefix
  project_id    = var.gcp_project_id
  zone          = var.gcp_zone
  subnet_id     = google_compute_subnetwork.db_vms.id
  dns_zone_name = trimsuffix(var.private_dns_zone_name, ".")

  depends_on = [module.db_spoke]
}

#####################
# Reserved Global External IPs for GKE Gateway API
#
# Each cluster's external Gateway resource (in nodes/*) attaches via the
# `networking.gke.io/addresses` annotation referencing these IP names. Reserving
# them here keeps DNS and downstream wiring stable across nodes layer rebuilds.
#####################

resource "google_compute_global_address" "frontend_gateway" {
  name         = "${var.name_prefix}-frontend-gateway-ip"
  project      = var.gcp_project_id
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

resource "google_compute_global_address" "backend_gateway" {
  name         = "${var.name_prefix}-backend-gateway-ip"
  project      = var.gcp_project_id
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

#####################
# Cloud DNS — Private Zone
#
# Visible inside all three VPCs (frontend, backend, db). Pod DNS resolves via
# kube-dns → Cloud DNS, so service FQDNs from ExternalDNS are reachable.
#####################

resource "google_dns_managed_zone" "main" {
  name        = "${var.name_prefix}-private-zone"
  project     = var.gcp_project_id
  dns_name    = var.private_dns_zone_name
  description = "Private zone for ${var.name_prefix} GKE multicluster blueprint"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = module.frontend_vpc.vpc_self_link
    }
    networks {
      network_url = module.backend_vpc.vpc_self_link
    }
    networks {
      network_url = google_compute_network.db.self_link
    }
  }
}

resource "google_dns_record_set" "db" {
  project      = var.gcp_project_id
  managed_zone = google_dns_managed_zone.main.name
  name         = "db.${var.private_dns_zone_name}"
  type         = "A"
  ttl          = 300
  rrdatas      = [module.db_vm.vm_private_ip]
}
