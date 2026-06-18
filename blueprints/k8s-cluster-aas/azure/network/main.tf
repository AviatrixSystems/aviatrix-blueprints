#####################
# Pattern A: Cluster-as-a-Service - Azure Network Layer (Layer 1)
#
# This layer provisions:
#   - Aviatrix Transit Gateway in Azure
#   - 3x team VNets (team-a, team-b, team-c) via aviatrix_vpc (cloud_type=8)
#   - 3x Aviatrix Spoke Gateways with single_ip_snat for pod traffic
#   - Database spoke VNet
#   - Azure Private DNS Zone for internal service discovery
#
# Architecture:
#   Transit GW (10.28.0.0/20)
#     ├── Team-A Spoke (10.30.0.0/20) - AKS cluster for team-a
#     ├── Team-B Spoke (10.31.0.0/20) - AKS cluster for team-b
#     ├── Team-C Spoke (10.32.0.0/20) - AKS cluster for team-c
#     └── Database Spoke (10.35.0.0/22) - Shared database
#
# Pod Networking:
#   Azure CNI Overlay with pod CIDR 100.64.0.0/16 (overlapping across VNets).
#   Pods use non-routable overlay addresses. Aviatrix SNAT translates pod traffic
#   to spoke gateway IPs for east-west and egress flows.
#
# CRITICAL LESSONS LEARNED:
#   - excluded_advertised_spoke_routes goes on the TRANSIT module, NOT on spokes
#   - This is software-defined routing via Aviatrix, not BGP from spokes
#   - DCF sees POST-SNAT traffic -- use VPC SmartGroups for source, hostname for dest
#   - Use aviatrix_vpc (cloud_type=8) for spoke VNets so Aviatrix manages route tables
#   - Azure-native route tables from aks-vnet module conflict with Aviatrix spoke gateways
#   - Extract ARM VNet ID from Aviatrix format: element(split(":", vpc_id), 0/1)
#   - VNet names use suffix "-vnet" -- SmartGroups must match e.g. "team-a-vnet"
#####################

provider "aviatrix" {
  skip_version_validation = true
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

resource "random_id" "suffix" {
  count       = var.random_suffix ? 1 : 0
  byte_length = 2
}

locals {
  name_prefix = var.random_suffix ? "${var.name_prefix}-${random_id.suffix[0].hex}" : var.name_prefix
  pod_cidr    = var.pod_cidr

  teams = {
    team-a = {
      name      = "team-a"
      vnet_cidr = var.team_a_vnet_cidr
    }
    team-b = {
      name      = "team-b"
      vnet_cidr = var.team_b_vnet_cidr
    }
    team-c = {
      name      = "team-c"
      vnet_cidr = var.team_c_vnet_cidr
    }
  }
}

#####################
# Aviatrix Transit Gateway
#####################

module "azure_transit" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "~> 8.2.0"

  name    = "${local.name_prefix}-transit"
  cloud   = "Azure"
  account = var.aviatrix_azure_account_name
  region  = var.azure_region
  cidr    = var.transit_cidr
  ha_gw   = false

  enable_transit_firenet        = true
  enable_egress_transit_firenet = false

  # Pattern A uses larger transit instance for 3 team spokes
  instance_size     = "Standard_D8s_v3"
  connected_transit = true

  enable_vpc_dns_server = true

  # CRITICAL: Exclude non-routable pod CIDR from BGP advertisements
  # This goes on the TRANSIT module, NOT on spokes.
  excluded_advertised_spoke_routes = local.pod_cidr
}

#####################
# Team-A VNet and Spoke
#
# Using aviatrix_vpc (cloud_type=8) instead of the aks-vnet module so that
# Aviatrix manages the route tables. This is required for SNAT to work
# correctly — Azure-native route tables conflict with Aviatrix spoke gateways.
#####################

resource "aviatrix_vpc" "team_a" {
  cloud_type           = 8 # Azure
  account_name         = var.aviatrix_azure_account_name
  name                 = "${local.name_prefix}-team-a-vnet"
  region               = var.azure_region
  cidr                 = local.teams["team-a"].vnet_cidr
  aviatrix_firenet_vpc = false
}

resource "aviatrix_spoke_gateway" "team_a" {
  cloud_type   = 8
  account_name = var.aviatrix_azure_account_name
  gw_name      = "${local.name_prefix}-team-a-spoke"
  vpc_id       = aviatrix_vpc.team_a.vpc_id
  vpc_reg      = var.azure_region
  gw_size      = "Standard_B2ms"
  subnet       = aviatrix_vpc.team_a.public_subnets[0].cidr

  single_ip_snat = true
}

resource "aviatrix_spoke_transit_attachment" "team_a" {
  spoke_gw_name   = aviatrix_spoke_gateway.team_a.gw_name
  transit_gw_name = module.azure_transit.transit_gateway.gw_name
}

#####################
# Team-B VNet and Spoke
#####################

resource "aviatrix_vpc" "team_b" {
  cloud_type           = 8 # Azure
  account_name         = var.aviatrix_azure_account_name
  name                 = "${local.name_prefix}-team-b-vnet"
  region               = var.azure_region
  cidr                 = local.teams["team-b"].vnet_cidr
  aviatrix_firenet_vpc = false
}

resource "aviatrix_spoke_gateway" "team_b" {
  cloud_type   = 8
  account_name = var.aviatrix_azure_account_name
  gw_name      = "${local.name_prefix}-team-b-spoke"
  vpc_id       = aviatrix_vpc.team_b.vpc_id
  vpc_reg      = var.azure_region
  gw_size      = "Standard_B2ms"
  subnet       = aviatrix_vpc.team_b.public_subnets[0].cidr

  single_ip_snat = true
}

resource "aviatrix_spoke_transit_attachment" "team_b" {
  spoke_gw_name   = aviatrix_spoke_gateway.team_b.gw_name
  transit_gw_name = module.azure_transit.transit_gateway.gw_name
}

#####################
# Team-C VNet and Spoke
#####################

resource "aviatrix_vpc" "team_c" {
  cloud_type           = 8 # Azure
  account_name         = var.aviatrix_azure_account_name
  name                 = "${local.name_prefix}-team-c-vnet"
  region               = var.azure_region
  cidr                 = local.teams["team-c"].vnet_cidr
  aviatrix_firenet_vpc = false
}

resource "aviatrix_spoke_gateway" "team_c" {
  cloud_type   = 8
  account_name = var.aviatrix_azure_account_name
  gw_name      = "${local.name_prefix}-team-c-spoke"
  vpc_id       = aviatrix_vpc.team_c.vpc_id
  vpc_reg      = var.azure_region
  gw_size      = "Standard_B2ms"
  subnet       = aviatrix_vpc.team_c.public_subnets[0].cidr

  single_ip_snat = true
}

resource "aviatrix_spoke_transit_attachment" "team_c" {
  spoke_gw_name   = aviatrix_spoke_gateway.team_c.gw_name
  transit_gw_name = module.azure_transit.transit_gateway.gw_name
}

#####################
# Database Spoke
#####################

module "spoke_db" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud          = "Azure"
  name           = "${local.name_prefix}-db-spoke"
  cidr           = var.db_vnet_cidr
  account        = var.aviatrix_azure_account_name
  region         = var.azure_region
  transit_gw     = module.azure_transit.transit_gateway.gw_name
  instance_size  = "Standard_B2ms"
  ha_gw          = false
  single_ip_snat = true

  enable_vpc_dns_server = true
}

#####################
# Azure Private DNS Zone
#####################

# Extract ARM VNet IDs for DNS links
# Aviatrix vpc_id format: "vnet_name:rg_name:guid"
locals {
  team_a_rg_name      = element(split(":", aviatrix_vpc.team_a.vpc_id), 1)
  team_a_arm_vnet_id  = "/subscriptions/${var.azure_subscription_id}/resourceGroups/${local.team_a_rg_name}/providers/Microsoft.Network/virtualNetworks/${element(split(":", aviatrix_vpc.team_a.vpc_id), 0)}"
  team_b_arm_vnet_id  = "/subscriptions/${var.azure_subscription_id}/resourceGroups/${element(split(":", aviatrix_vpc.team_b.vpc_id), 1)}/providers/Microsoft.Network/virtualNetworks/${element(split(":", aviatrix_vpc.team_b.vpc_id), 0)}"
  team_c_arm_vnet_id  = "/subscriptions/${var.azure_subscription_id}/resourceGroups/${element(split(":", aviatrix_vpc.team_c.vpc_id), 1)}/providers/Microsoft.Network/virtualNetworks/${element(split(":", aviatrix_vpc.team_c.vpc_id), 0)}"
  transit_arm_vnet_id = "/subscriptions/${var.azure_subscription_id}/resourceGroups/${element(split(":", module.azure_transit.vpc.vpc_id), 1)}/providers/Microsoft.Network/virtualNetworks/${element(split(":", module.azure_transit.vpc.vpc_id), 0)}"
}

resource "azurerm_private_dns_zone" "this" {
  name                = var.private_dns_zone_name
  resource_group_name = local.team_a_rg_name

  tags = {
    Environment = "demo"
    Terraform   = "true"
    Pattern     = "cluster-aas"
  }
}

# Link DNS zone to all team VNets
resource "azurerm_private_dns_zone_virtual_network_link" "team_a" {
  name                  = "team-a-dns-link"
  resource_group_name   = local.team_a_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = local.team_a_arm_vnet_id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "team_b" {
  name                  = "team-b-dns-link"
  resource_group_name   = local.team_a_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = local.team_b_arm_vnet_id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "team_c" {
  name                  = "team-c-dns-link"
  resource_group_name   = local.team_a_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = local.team_c_arm_vnet_id
  registration_enabled  = false
}

# Link DNS zone to transit VNet
resource "azurerm_private_dns_zone_virtual_network_link" "transit" {
  name                  = "transit-dns-link"
  resource_group_name   = local.team_a_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = local.transit_arm_vnet_id
  registration_enabled  = false
}

#####################
# Static DNS Records
#####################

resource "azurerm_private_dns_a_record" "db" {
  name                = "db"
  zone_name           = azurerm_private_dns_zone.this.name
  resource_group_name = local.team_a_rg_name
  ttl                 = 300
  records             = [var.db_private_ip]
}
