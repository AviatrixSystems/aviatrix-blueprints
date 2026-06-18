#####################
# Pattern A: Cluster-as-a-Service - GCP Network Layer (Layer 1)
#
# This layer provisions:
#   - Aviatrix Transit Gateway in GCP
#   - 3x team VPCs (team-a, team-b, team-c) via gke-vpc module
#   - 3x Aviatrix Spoke Gateways (active/active) with custom SNAT for pod traffic
#   - Database spoke VPC
#   - Cloud DNS Private Zone for internal service discovery
#
# Architecture:
#   Transit GW (10.38.0.0/20)
#     ├── Team-A Spoke (10.40.0.0/20) - GKE cluster for team-a
#     ├── Team-B Spoke (10.41.0.0/20) - GKE cluster for team-b
#     ├── Team-C Spoke (10.42.0.0/20) - GKE cluster for team-c
#     └── Database Spoke (10.45.0.0/22) - Shared database
#
# Pod Networking:
#   VPC-native alias IPs with pod CIDR 100.64.0.0/16 (overlapping across VPCs).
#   Pods use non-routable secondary range addresses. Aviatrix SNAT translates pod
#   traffic to spoke gateway IPs for east-west and egress flows.
#
# CRITICAL LESSONS LEARNED:
#   - excluded_advertised_spoke_routes goes on the TRANSIT module, NOT on spokes
#   - This is software-defined routing via Aviatrix, not BGP from spokes
#   - Gateways are Active/Active, not standby
#   - DCF sees POST-SNAT traffic -- use VPC SmartGroups for source, hostname for dest
#   - DNS network_url needs GCP self-link format, not Aviatrix format
#   - Unique master_ipv4_cidr_block per cluster (172.16.0.0/28, .16/28, .32/28)
#   - deletion_protection = false for demo environments
#####################

provider "aviatrix" {
  skip_version_validation = true
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

resource "random_id" "suffix" {
  count       = var.random_suffix ? 1 : 0
  byte_length = 2
}

locals {
  name_prefix   = var.random_suffix ? "${var.name_prefix}-${random_id.suffix[0].hex}" : var.name_prefix
  pod_cidr      = var.pod_cidr
  services_cidr = var.services_cidr

  teams = {
    team-a = {
      name         = "${local.name_prefix}-team-a"
      primary_cidr = var.team_a_vpc_cidr
      master_cidr  = var.team_a_master_cidr
    }
    team-b = {
      name         = "${local.name_prefix}-team-b"
      primary_cidr = var.team_b_vpc_cidr
      master_cidr  = var.team_b_master_cidr
    }
    team-c = {
      name         = "${local.name_prefix}-team-c"
      primary_cidr = var.team_c_vpc_cidr
      master_cidr  = var.team_c_master_cidr
    }
  }
}

#####################
# Aviatrix Transit Gateway
#####################

module "gcp_transit" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "~> 8.2.0"

  name    = "${local.name_prefix}-transit"
  cloud   = "GCP"
  account = var.aviatrix_gcp_account_name
  region  = var.gcp_region
  cidr    = var.transit_cidr
  ha_gw   = false

  enable_transit_firenet        = false
  enable_egress_transit_firenet = false

  instance_size     = "n1-standard-4"
  connected_transit = true


  # CRITICAL: Exclude non-routable pod CIDR from BGP advertisements
  # This goes on the TRANSIT module, NOT on spokes.
  excluded_advertised_spoke_routes = local.pod_cidr
}

#####################
# Team-A VPC and Spoke
#####################

# Module source: ../../../gcp-gke-multicluster/network/modules/gke-vpc
module "team_a_vpc" {
  source = "../../../gcp-gke-multicluster/network/modules/gke-vpc"

  name    = local.teams["team-a"].name
  project = var.gcp_project
  region  = var.gcp_region

  primary_cidr           = local.teams["team-a"].primary_cidr
  pod_cidr               = local.pod_cidr
  services_cidr          = local.services_cidr
  master_ipv4_cidr_block = local.teams["team-a"].master_cidr
}

module "team_a_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud      = "GCP"
  name       = "${local.name_prefix}-team-a-spoke"
  account    = var.aviatrix_gcp_account_name
  region     = var.gcp_region
  transit_gw = module.gcp_transit.transit_gateway.gw_name

  # Active/Active gateways - NOT standby
  instance_size = "n1-standard-2"
  ha_gw         = false


  # GCP VPC format: "network_name~~project_id"
  use_existing_vpc = true
  vpc_id           = "${module.team_a_vpc.network_name}~~${var.gcp_project}"
  gw_subnet        = module.team_a_vpc.avx_gateway_subnet_cidr
  hagw_subnet      = module.team_a_vpc.avx_gateway_subnet_cidr
}

# CRITICAL: Custom SNAT for pod traffic (100.64.0.0/16 -> spoke gateway IP)
resource "aviatrix_gateway_snat" "team_a_spoke_snat" {
  gw_name   = module.team_a_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.gcp_transit.transit_gateway.gw_name
    snat_ips   = module.team_a_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_a_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = module.team_a_vpc.gke_nodes_subnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_a_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.team_a_spoke]
}

#####################
# Team-B VPC and Spoke
#####################

module "team_b_vpc" {
  source = "../../../gcp-gke-multicluster/network/modules/gke-vpc"

  name    = local.teams["team-b"].name
  project = var.gcp_project
  region  = var.gcp_region

  primary_cidr           = local.teams["team-b"].primary_cidr
  pod_cidr               = local.pod_cidr
  services_cidr          = local.services_cidr
  master_ipv4_cidr_block = local.teams["team-b"].master_cidr
}

module "team_b_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud      = "GCP"
  name       = "${local.name_prefix}-team-b-spoke"
  account    = var.aviatrix_gcp_account_name
  region     = var.gcp_region
  transit_gw = module.gcp_transit.transit_gateway.gw_name

  instance_size = "n1-standard-2"
  ha_gw         = false


  use_existing_vpc = true
  vpc_id           = "${module.team_b_vpc.network_name}~~${var.gcp_project}"
  gw_subnet        = module.team_b_vpc.avx_gateway_subnet_cidr
  hagw_subnet      = module.team_b_vpc.avx_gateway_subnet_cidr
}

resource "aviatrix_gateway_snat" "team_b_spoke_snat" {
  gw_name   = module.team_b_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.gcp_transit.transit_gateway.gw_name
    snat_ips   = module.team_b_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_b_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = module.team_b_vpc.gke_nodes_subnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_b_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.team_b_spoke]
}

#####################
# Team-C VPC and Spoke
#####################

module "team_c_vpc" {
  source = "../../../gcp-gke-multicluster/network/modules/gke-vpc"

  name    = local.teams["team-c"].name
  project = var.gcp_project
  region  = var.gcp_region

  primary_cidr           = local.teams["team-c"].primary_cidr
  pod_cidr               = local.pod_cidr
  services_cidr          = local.services_cidr
  master_ipv4_cidr_block = local.teams["team-c"].master_cidr
}

module "team_c_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud      = "GCP"
  name       = "${local.name_prefix}-team-c-spoke"
  account    = var.aviatrix_gcp_account_name
  region     = var.gcp_region
  transit_gw = module.gcp_transit.transit_gateway.gw_name

  instance_size = "n1-standard-2"
  ha_gw         = false


  use_existing_vpc = true
  vpc_id           = "${module.team_c_vpc.network_name}~~${var.gcp_project}"
  gw_subnet        = module.team_c_vpc.avx_gateway_subnet_cidr
  hagw_subnet      = module.team_c_vpc.avx_gateway_subnet_cidr
}

resource "aviatrix_gateway_snat" "team_c_spoke_snat" {
  gw_name   = module.team_c_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.gcp_transit.transit_gateway.gw_name
    snat_ips   = module.team_c_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_c_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = module.team_c_vpc.gke_nodes_subnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.team_c_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.team_c_spoke]
}

#####################
# Database Spoke
#####################

module "spoke_db" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud          = "GCP"
  name           = "${local.name_prefix}-db-spoke"
  cidr           = var.db_vpc_cidr
  account        = var.aviatrix_gcp_account_name
  region         = var.gcp_region
  transit_gw     = module.gcp_transit.transit_gateway.gw_name
  instance_size  = "n1-standard-2"
  ha_gw          = false
  single_ip_snat = true

}

#####################
# Cloud DNS Private Zone
#
# CRITICAL: DNS network_url needs GCP self-link format, not Aviatrix format.
# For Aviatrix-managed VPCs, extract network name from vpc_id and build self-link.
#####################

resource "google_dns_managed_zone" "private" {
  name        = replace(var.dns_private_zone_name, ".", "-")
  project     = var.gcp_project
  dns_name    = "${var.dns_private_zone_name}."
  description = "Private DNS zone for Pattern A Cluster-as-a-Service"
  visibility  = "private"

  private_visibility_config {
    # Associate with transit VPC
    # CRITICAL: Use GCP self-link format for transit VPC, not Aviatrix format
    networks {
      network_url = "projects/${var.gcp_project}/global/networks/${split("~-~", module.gcp_transit.vpc.vpc_id)[0]}"
    }

    # Associate with team VPCs (these use module output which is already self-link format)
    networks {
      network_url = module.team_a_vpc.network_id
    }
    networks {
      network_url = module.team_b_vpc.network_id
    }
    networks {
      network_url = module.team_c_vpc.network_id
    }
  }

  labels = {
    environment = "demo"
    terraform   = "true"
    pattern     = "cluster-aas"
  }
}

#####################
# Static DNS Records
#####################

resource "google_dns_record_set" "db" {
  name         = "db.${var.dns_private_zone_name}."
  project      = var.gcp_project
  managed_zone = google_dns_managed_zone.private.name
  type         = "A"
  ttl          = 300
  rrdatas      = [cidrhost(var.db_vpc_cidr, 10)]
}
