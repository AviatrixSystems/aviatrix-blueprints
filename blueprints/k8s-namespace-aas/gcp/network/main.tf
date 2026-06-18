#####################
# Pattern B: Namespace-as-a-Service — GCP Network Layer (Layer 1)
#
# This layer provisions:
#   - Aviatrix Transit Gateway in GCP
#   - 1 shared cluster VPC (all teams share a single GKE cluster)
#   - 1 Aviatrix Spoke Gateway with custom SNAT for pod traffic
#   - Cloud DNS Private Zone for internal DNS
#
# Architecture:
#   Transit GW (10.38.0.0/20)
#     └── Shared Cluster Spoke (10.40.0.0/16) - single GKE cluster for all teams
#
# Team isolation is enforced by DCF SmartGroups keyed on k8s_namespace,
# NOT by separate VPCs or Kubernetes RBAC alone.
# RBAC is NOT a hard security boundary — DCF is the primary network isolation.
#
# Pod Networking:
#   GKE VPC-native with alias IP ranges. Pod CIDR 100.64.0.0/16 is assigned as
#   a secondary range. Aviatrix SNAT translates pod traffic to spoke gateway IPs
#   for east-west and egress flows.
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
  name_prefix      = var.random_suffix ? "${var.name_prefix}-${random_id.suffix[0].hex}" : var.name_prefix
  pod_cidr         = var.pod_cidr
  services_cidr    = var.services_cidr
  k8s_cluster_name = "${local.name_prefix}-${var.k8s_cluster_suffix}"
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

  instance_size     = "n1-standard-2"
  connected_transit = true

  # Use VPC DNS server for gateway management — required for hostname SmartGroups

  # CRITICAL: Exclude non-routable pod CIDR from BGP advertisements
  # This allows spokes with the same secondary range (100.64.0.0/16)
  excluded_advertised_spoke_routes = local.pod_cidr
}

#####################
# Shared Cluster VPC
#
# Unlike Pattern A (Cluster-as-a-Service) which creates 1 VPC per team,
# Pattern B uses a single VPC for the shared cluster. All teams' namespaces
# run in the same GKE cluster within this VPC.
#####################

module "shared_vpc" {
  source = "../../../gcp-gke-multicluster/network/modules/gke-vpc"

  name    = "${local.name_prefix}-shared"
  project = var.gcp_project
  region  = var.gcp_region

  primary_cidr           = var.shared_vpc_cidr
  pod_cidr               = local.pod_cidr
  services_cidr          = local.services_cidr
  master_ipv4_cidr_block = var.master_ipv4_cidr_block
}

#####################
# Spoke Gateway (Shared Cluster VPC)
#####################

module "shared_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud      = "GCP"
  name       = "${local.name_prefix}-shared-spoke"
  account    = var.aviatrix_gcp_account_name
  region     = var.gcp_region
  transit_gw = module.gcp_transit.transit_gateway.gw_name

  instance_size = "n1-standard-2"
  ha_gw         = false

  # Use VPC DNS server for gateway management — required for hostname SmartGroups

  # Use existing VPC created by gke-vpc module
  use_existing_vpc = true
  vpc_id           = "${module.shared_vpc.network_name}~~${var.gcp_project}"
  gw_subnet        = module.shared_vpc.avx_gateway_subnet_cidr
  hagw_subnet      = module.shared_vpc.avx_gateway_subnet_cidr
}

# CRITICAL: Custom SNAT for pod traffic (100.64.0.0/16 -> spoke gateway IP)
#
# GKE uses alias IP ranges (VPC-native) instead of AWS ENIConfig.
# Pod traffic from alias IPs (100.64.x.x) is NOT routable across VPCs.
# Aviatrix spoke gateway SNAT translates pod IPs to the gateway's routable IP.
# DCF sees POST-SNAT traffic, so use VPC-type SmartGroups for source matching.
resource "aviatrix_gateway_snat" "shared_spoke_snat" {
  gw_name   = module.shared_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  # SNAT for pod CIDR to all destinations via transit
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.gcp_transit.transit_gateway.gw_name
    snat_ips   = module.shared_spoke.spoke_gateway.private_ip
  }

  # SNAT for pod CIDR to internet via eth0
  snat_policy {
    src_cidr   = local.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.shared_spoke.spoke_gateway.private_ip
  }

  # SNAT for GKE node subnet to internet via eth0
  snat_policy {
    src_cidr   = module.shared_vpc.gke_nodes_subnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.shared_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.shared_spoke]
}

#####################
# Cloud DNS Private Zone
#
# DNS network_url needs GCP self-link, not Aviatrix format.
# For transit VPC: split "name~~project" and reconstruct self-link.
#####################

resource "google_dns_managed_zone" "private" {
  name        = replace(var.dns_private_zone_name, ".", "-")
  project     = var.gcp_project
  dns_name    = "${var.dns_private_zone_name}."
  description = "Private DNS zone for NaaS shared GKE cluster"
  visibility  = "private"

  private_visibility_config {
    # Associate with shared cluster VPC
    networks {
      network_url = module.shared_vpc.network_id
    }

    # Associate with transit VPC
    # DNS network_url needs GCP self-link, not Aviatrix format
    networks {
      network_url = "projects/${var.gcp_project}/global/networks/${split("~-~", module.gcp_transit.vpc.vpc_id)[0]}"
    }
  }

  labels = {
    environment = var.env
    pattern     = "namespace-aas"
    terraform   = "true"
  }
}
