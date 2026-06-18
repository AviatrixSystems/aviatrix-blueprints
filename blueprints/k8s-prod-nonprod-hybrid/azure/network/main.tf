# -----------------------------------------------------------------------------
# Pattern C: Prod/Non-Prod + Namespace-as-a-Service — Azure Network
# RECOMMENDED pattern for most organizations
#
# Architecture:
#   1 Transit Gateway
#   2 Spoke Gateways: prod VNet + nonprod VNet (each in own VNet)
#   1 DB Spoke Gateway (prod data only)
#   SNAT + DNS configured per spoke
# -----------------------------------------------------------------------------

provider "aviatrix" {
  controller_ip = var.aviatrix_controller_ip
  username      = var.aviatrix_username
  password      = var.aviatrix_password
}

provider "azurerm" {
  features {}
}

resource "random_id" "suffix" {
  count       = var.random_suffix ? 1 : 0
  byte_length = 2
}

# ---------------------------------------------------------------------------
# Transit VNet + Gateway
# ---------------------------------------------------------------------------

resource "aviatrix_vpc" "transit" {
  cloud_type           = 8 # Azure
  account_name         = var.azure_account_name
  name                 = "${local.name_prefix}-transit-vnet"
  region               = var.azure_region
  cidr                 = var.transit_cidr
  aviatrix_firenet_vpc = false
}

resource "aviatrix_transit_gateway" "main" {
  cloud_type   = 8
  account_name = var.azure_account_name
  gw_name      = "${local.name_prefix}-transit"
  vpc_id       = aviatrix_vpc.transit.vpc_id
  vpc_reg      = var.azure_region
  gw_size      = var.transit_gw_size
  subnet       = aviatrix_vpc.transit.public_subnets[0].cidr

  enable_transit_firenet              = true
  enable_segmentation                 = true
  enable_transit_summarize_cidr_to_tgw = false
  connected_transit                   = true
  ha_gw_size                          = var.enable_ha ? var.transit_gw_size : null
  ha_subnet                           = var.enable_ha ? aviatrix_vpc.transit.public_subnets[1].cidr : null
}

# ---------------------------------------------------------------------------
# Production VNet + Spoke Gateway
# ---------------------------------------------------------------------------

resource "aviatrix_vpc" "prod" {
  cloud_type           = 8
  account_name         = var.azure_account_name
  name                 = "${local.name_prefix}-prod-vnet"
  region               = var.azure_region
  cidr                 = var.prod_vnet_cidr
  aviatrix_firenet_vpc = false
}

resource "aviatrix_spoke_gateway" "prod" {
  cloud_type   = 8
  account_name = var.azure_account_name
  gw_name      = "${local.name_prefix}-prod-spoke"
  vpc_id       = aviatrix_vpc.prod.vpc_id
  vpc_reg      = var.azure_region
  gw_size      = var.spoke_gw_size
  subnet       = aviatrix_vpc.prod.public_subnets[0].cidr

  single_ip_snat = true

  ha_gw_size = var.enable_ha ? var.spoke_gw_size : null
  ha_subnet  = var.enable_ha ? aviatrix_vpc.prod.public_subnets[1].cidr : null
}

resource "aviatrix_spoke_transit_attachment" "prod" {
  spoke_gw_name   = aviatrix_spoke_gateway.prod.gw_name
  transit_gw_name = aviatrix_transit_gateway.main.gw_name
}

# ---------------------------------------------------------------------------
# Non-Production VNet + Spoke Gateway
# ---------------------------------------------------------------------------

resource "aviatrix_vpc" "nonprod" {
  cloud_type           = 8
  account_name         = var.azure_account_name
  name                 = "${local.name_prefix}-nonprod-vnet"
  region               = var.azure_region
  cidr                 = var.nonprod_vnet_cidr
  aviatrix_firenet_vpc = false
}

resource "aviatrix_spoke_gateway" "nonprod" {
  cloud_type   = 8
  account_name = var.azure_account_name
  gw_name      = "${local.name_prefix}-nonprod-spoke"
  vpc_id       = aviatrix_vpc.nonprod.vpc_id
  vpc_reg      = var.azure_region
  gw_size      = var.spoke_gw_size
  subnet       = aviatrix_vpc.nonprod.public_subnets[0].cidr

  single_ip_snat = true

  ha_gw_size = var.enable_ha ? var.spoke_gw_size : null
  ha_subnet  = var.enable_ha ? aviatrix_vpc.nonprod.public_subnets[1].cidr : null
}

resource "aviatrix_spoke_transit_attachment" "nonprod" {
  spoke_gw_name   = aviatrix_spoke_gateway.nonprod.gw_name
  transit_gw_name = aviatrix_transit_gateway.main.gw_name
}

# ---------------------------------------------------------------------------
# Database Spoke (prod data only)
# ---------------------------------------------------------------------------

resource "aviatrix_vpc" "db" {
  cloud_type           = 8
  account_name         = var.azure_account_name
  name                 = "${local.name_prefix}-prod-db-vnet"
  region               = var.azure_region
  cidr                 = var.db_spoke_cidr
  aviatrix_firenet_vpc = false
}

resource "aviatrix_spoke_gateway" "db" {
  cloud_type   = 8
  account_name = var.azure_account_name
  gw_name      = "${local.name_prefix}-db-spoke"
  vpc_id       = aviatrix_vpc.db.vpc_id
  vpc_reg      = var.azure_region
  gw_size      = var.db_spoke_gw_size
  subnet       = aviatrix_vpc.db.public_subnets[0].cidr

  ha_gw_size = var.enable_ha ? var.db_spoke_gw_size : null
  ha_subnet  = var.enable_ha ? aviatrix_vpc.db.public_subnets[1].cidr : null
}

resource "aviatrix_spoke_transit_attachment" "db" {
  spoke_gw_name   = aviatrix_spoke_gateway.db.gw_name
  transit_gw_name = aviatrix_transit_gateway.main.gw_name
}

# ---------------------------------------------------------------------------
# Resource Group for DNS and shared resources
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.azure_region

  tags = {
    Environment = "demo"
    Pattern     = "prod-nonprod-hybrid"
    Terraform   = "true"
  }
}

# ---------------------------------------------------------------------------
# DNS — Azure Private DNS Zone
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "internal" {
  name                = var.dns_domain
  resource_group_name = azurerm_resource_group.main.name
}

# Extract ARM VNet IDs for DNS links
locals {
  name_prefix         = var.random_suffix ? "${var.environment_prefix}-${random_id.suffix[0].hex}" : var.environment_prefix
  prod_arm_vnet_id    = "/subscriptions/${var.azure_subscription_id}/resourceGroups/${element(split(":", aviatrix_vpc.prod.vpc_id), 1)}/providers/Microsoft.Network/virtualNetworks/${element(split(":", aviatrix_vpc.prod.vpc_id), 0)}"
  nonprod_arm_vnet_id = "/subscriptions/${var.azure_subscription_id}/resourceGroups/${element(split(":", aviatrix_vpc.nonprod.vpc_id), 1)}/providers/Microsoft.Network/virtualNetworks/${element(split(":", aviatrix_vpc.nonprod.vpc_id), 0)}"
}

resource "azurerm_private_dns_zone_virtual_network_link" "prod" {
  name                  = "${local.name_prefix}-prod-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.internal.name
  virtual_network_id    = local.prod_arm_vnet_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "nonprod" {
  name                  = "${local.name_prefix}-nonprod-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.internal.name
  virtual_network_id    = local.nonprod_arm_vnet_id
}
