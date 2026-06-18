# -----------------------------------------------------------------------------
# Pattern C: Prod/Non-Prod + Namespace-as-a-Service — GCP Network
# RECOMMENDED pattern for most organizations
#
# Architecture:
#   1 Transit Gateway
#   2 Spoke Gateways: prod VPC + nonprod VPC (each in own VPC)
#   1 DB Spoke Gateway (prod data only)
#   SNAT + DNS configured per spoke
# -----------------------------------------------------------------------------

provider "aviatrix" {
  controller_ip = var.aviatrix_controller_ip
  username      = var.aviatrix_username
  password      = var.aviatrix_password
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

resource "random_id" "suffix" {
  count       = var.random_suffix ? 1 : 0
  byte_length = 2
}

locals {
  name_prefix = var.random_suffix ? "${var.environment_prefix}-${random_id.suffix[0].hex}" : var.environment_prefix
}

# ---------------------------------------------------------------------------
# Transit VPC + Gateway
# ---------------------------------------------------------------------------

resource "aviatrix_vpc" "transit" {
  cloud_type   = 4 # GCP
  account_name = var.gcp_account_name
  name         = "${local.name_prefix}-transit"

  subnets {
    name   = "${local.name_prefix}-transit-subnet"
    cidr   = var.transit_cidr
    region = var.gcp_region
  }
}

resource "aviatrix_transit_gateway" "main" {
  cloud_type   = 4
  account_name = var.gcp_account_name
  gw_name      = "${local.name_prefix}-transit"
  vpc_id       = aviatrix_vpc.transit.vpc_id
  vpc_reg      = "${var.gcp_region}-b"
  gw_size      = var.transit_gw_size
  subnet       = var.transit_cidr

  enable_transit_firenet              = false
  enable_segmentation                 = true
  enable_transit_summarize_cidr_to_tgw = false
  connected_transit                   = true
  ha_gw_size                          = var.enable_ha ? var.transit_gw_size : null
  ha_subnet                           = var.enable_ha ? var.transit_cidr : null
  ha_zone                             = var.enable_ha ? "${var.gcp_region}-b" : null
}

# ---------------------------------------------------------------------------
# Production VPC + Spoke Gateway
# ---------------------------------------------------------------------------

resource "aviatrix_vpc" "prod" {
  cloud_type           = 4
  account_name         = var.gcp_account_name
  name                 = "${local.name_prefix}-prod"
  aviatrix_firenet_vpc = false

  subnets {
    name   = "${local.name_prefix}-prod-subnet"
    cidr   = var.prod_vpc_cidr
    region = var.gcp_region
  }
}

resource "aviatrix_spoke_gateway" "prod" {
  cloud_type   = 4
  account_name = var.gcp_account_name
  gw_name      = "${local.name_prefix}-prod-spoke"
  vpc_id       = aviatrix_vpc.prod.vpc_id
  vpc_reg      = "${var.gcp_region}-b"
  gw_size      = var.spoke_gw_size
  subnet       = var.prod_vpc_cidr

  single_ip_snat = true

  ha_gw_size = var.enable_ha ? var.spoke_gw_size : null
  ha_subnet  = var.enable_ha ? var.prod_vpc_cidr : null
  ha_zone    = var.enable_ha ? "${var.gcp_region}-c" : null
}

resource "aviatrix_spoke_transit_attachment" "prod" {
  spoke_gw_name   = aviatrix_spoke_gateway.prod.gw_name
  transit_gw_name = aviatrix_transit_gateway.main.gw_name
}

# ---------------------------------------------------------------------------
# Non-Production VPC + Spoke Gateway
# ---------------------------------------------------------------------------

resource "aviatrix_vpc" "nonprod" {
  cloud_type           = 4
  account_name         = var.gcp_account_name
  name                 = "${local.name_prefix}-nonprod"
  aviatrix_firenet_vpc = false

  subnets {
    name   = "${local.name_prefix}-nonprod-subnet"
    cidr   = var.nonprod_vpc_cidr
    region = var.gcp_region
  }
}

resource "aviatrix_spoke_gateway" "nonprod" {
  cloud_type   = 4
  account_name = var.gcp_account_name
  gw_name      = "${local.name_prefix}-nonprod-spoke"
  vpc_id       = aviatrix_vpc.nonprod.vpc_id
  vpc_reg      = "${var.gcp_region}-b"
  gw_size      = var.spoke_gw_size
  subnet       = var.nonprod_vpc_cidr

  single_ip_snat = true

  ha_gw_size = var.enable_ha ? var.spoke_gw_size : null
  ha_subnet  = var.enable_ha ? var.nonprod_vpc_cidr : null
  ha_zone    = var.enable_ha ? "${var.gcp_region}-c" : null
}

resource "aviatrix_spoke_transit_attachment" "nonprod" {
  spoke_gw_name   = aviatrix_spoke_gateway.nonprod.gw_name
  transit_gw_name = aviatrix_transit_gateway.main.gw_name
}

# ---------------------------------------------------------------------------
# Database Spoke (prod data only)
# ---------------------------------------------------------------------------

resource "aviatrix_vpc" "db" {
  cloud_type           = 4
  account_name         = var.gcp_account_name
  name                 = "${local.name_prefix}-prod-db"
  aviatrix_firenet_vpc = false

  subnets {
    name   = "${local.name_prefix}-db-subnet"
    cidr   = var.db_spoke_cidr
    region = var.gcp_region
  }
}

resource "aviatrix_spoke_gateway" "db" {
  cloud_type   = 4
  account_name = var.gcp_account_name
  gw_name      = "${local.name_prefix}-db-spoke"
  vpc_id       = aviatrix_vpc.db.vpc_id
  vpc_reg      = "${var.gcp_region}-b"
  gw_size      = var.db_spoke_gw_size
  subnet       = var.db_spoke_cidr

  ha_gw_size = var.enable_ha ? var.db_spoke_gw_size : null
  ha_subnet  = var.enable_ha ? var.db_spoke_cidr : null
  ha_zone    = var.enable_ha ? "${var.gcp_region}-c" : null
}

resource "aviatrix_spoke_transit_attachment" "db" {
  spoke_gw_name   = aviatrix_spoke_gateway.db.gw_name
  transit_gw_name = aviatrix_transit_gateway.main.gw_name
}

# ---------------------------------------------------------------------------
# DNS — Cloud DNS Private Zone
# network_url: GCP self-link for Aviatrix transit VPC
# ---------------------------------------------------------------------------

resource "google_dns_managed_zone" "internal" {
  name        = "${local.name_prefix}-internal"
  dns_name    = "${var.dns_domain}."
  description = "Private DNS zone for Pattern C services"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = "projects/${var.gcp_project_id}/global/networks/${split("~-~", aviatrix_vpc.transit.vpc_id)[0]}"
    }
    networks {
      network_url = "projects/${var.gcp_project_id}/global/networks/${split("~-~", aviatrix_vpc.prod.vpc_id)[0]}"
    }
    networks {
      network_url = "projects/${var.gcp_project_id}/global/networks/${split("~-~", aviatrix_vpc.nonprod.vpc_id)[0]}"
    }
  }
}
