#####################
# Pattern B: Namespace-as-a-Service — Azure Network Layer (Layer 1)
#
# This layer provisions:
#   - Aviatrix Transit Gateway in Azure
#   - 1 shared cluster VNet via aviatrix_vpc (cloud_type=8)
#   - 1 Aviatrix Spoke Gateway with single_ip_snat for pod traffic
#   - Azure Private DNS Zone for internal DNS
#
# Architecture:
#   Transit GW (10.28.0.0/20)
#     └── Shared Cluster Spoke (10.30.0.0/16) - single AKS cluster for all teams
#
# Team isolation is enforced by DCF SmartGroups keyed on k8s_namespace,
# NOT by separate VNets or Kubernetes RBAC alone.
# RBAC is NOT a hard security boundary — DCF is the primary network isolation.
#
# Pod Networking:
#   Azure CNI Overlay with pod CIDR 100.64.0.0/16.
#   Pods use non-routable overlay addresses. Aviatrix SNAT translates pod traffic
#   to spoke gateway IPs for east-west and egress flows.
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
  name_prefix      = var.random_suffix ? "${var.name_prefix}-${random_id.suffix[0].hex}" : var.name_prefix
  pod_cidr         = var.pod_cidr
  k8s_cluster_name = "${local.name_prefix}-${var.k8s_cluster_suffix}"
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

  # Enable FireNet for future NGFW integration
  enable_transit_firenet        = true
  enable_egress_transit_firenet = false

  instance_size     = "Standard_B2ms"
  connected_transit = true

  # Use VPC DNS server for gateway management — required for hostname SmartGroups
  enable_vpc_dns_server = true

  # CRITICAL: Exclude non-routable pod CIDR from BGP advertisements
  # This allows spokes with the same overlay CIDR (100.64.0.0/16)
  excluded_advertised_spoke_routes = local.pod_cidr
}

#####################
# Shared Cluster VNet
#
# Unlike Pattern A (Cluster-as-a-Service) which creates 1 VNet per team,
# Pattern B uses a single VNet for the shared cluster. All teams' namespaces
# run in the same AKS cluster within this VNet.
#
# Using aviatrix_vpc (cloud_type=8) instead of the aks-vnet module so that
# Aviatrix manages the route tables. This is required for SNAT to work
# correctly — Azure-native route tables conflict with Aviatrix spoke gateways.
#####################

resource "aviatrix_vpc" "shared" {
  cloud_type           = 8 # Azure
  account_name         = var.aviatrix_azure_account_name
  name                 = "${local.name_prefix}-shared-vnet"
  region               = var.azure_region
  cidr                 = var.shared_vnet_cidr
  aviatrix_firenet_vpc = false
}

#####################
# Spoke Gateway (Shared Cluster VNet)
#
# single_ip_snat = true replaces the old aviatrix_gateway_snat resource.
# Aviatrix handles all SNAT for pod and node traffic automatically.
#####################

resource "aviatrix_spoke_gateway" "shared" {
  cloud_type   = 8
  account_name = var.aviatrix_azure_account_name
  gw_name      = "${local.name_prefix}-shared-spoke"
  vpc_id       = aviatrix_vpc.shared.vpc_id
  vpc_reg      = var.azure_region
  gw_size      = "Standard_B2ms"
  subnet       = aviatrix_vpc.shared.public_subnets[0].cidr

  single_ip_snat = true
}

resource "aviatrix_spoke_transit_attachment" "shared" {
  spoke_gw_name   = aviatrix_spoke_gateway.shared.gw_name
  transit_gw_name = module.azure_transit.transit_gateway.gw_name
}

#####################
# Azure Private DNS Zone
#
# Private DNS zones in Azure are global resources linked to VNets.
# Each linked VNet can resolve records in the zone.
#####################

# Extract ARM VNet IDs for DNS links
# Aviatrix vpc_id format: "vnet_name:rg_name:guid"
locals {
  shared_rg_name      = element(split(":", aviatrix_vpc.shared.vpc_id), 1)
  shared_arm_vnet_id  = "/subscriptions/${var.azure_subscription_id}/resourceGroups/${local.shared_rg_name}/providers/Microsoft.Network/virtualNetworks/${element(split(":", aviatrix_vpc.shared.vpc_id), 0)}"
  transit_arm_vnet_id = "/subscriptions/${var.azure_subscription_id}/resourceGroups/${element(split(":", module.azure_transit.vpc.vpc_id), 1)}/providers/Microsoft.Network/virtualNetworks/${element(split(":", module.azure_transit.vpc.vpc_id), 0)}"
}

resource "azurerm_private_dns_zone" "this" {
  name                = var.private_dns_zone_name
  resource_group_name = local.shared_rg_name

  tags = {
    Environment = var.env
    Pattern     = "namespace-aas"
    Terraform   = "true"
  }
}

# Link DNS zone to shared cluster VNet
resource "azurerm_private_dns_zone_virtual_network_link" "shared" {
  name                  = "shared-cluster-dns-link"
  resource_group_name   = local.shared_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = local.shared_arm_vnet_id
  registration_enabled  = false
}

# Link DNS zone to transit VNet
resource "azurerm_private_dns_zone_virtual_network_link" "transit" {
  name                  = "transit-dns-link"
  resource_group_name   = local.shared_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = local.transit_arm_vnet_id
  registration_enabled  = false
}
