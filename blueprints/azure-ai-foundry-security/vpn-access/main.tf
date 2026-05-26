# ══════════════════════════════════════════════════════════════════════════════
# VPN Access — Aviatrix P2S Gateway
# ══════════════════════════════════════════════════════════════════════════════

# ── Foundry VNet reference ────────────────────────────────────────────────────

data "azurerm_virtual_network" "foundry" {
  name                = local.vnet_name
  resource_group_name = local.vnet_resource_group
}

# ── VPN gateway subnet (added to the existing foundry VNet) ──────────────────
# No random suffix needed — subnet names are scoped inside the VNet.

resource "azurerm_subnet" "vpn_gw" {
  name                 = "snet-avx-vpn-gw"
  resource_group_name  = local.vnet_resource_group
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.vpn_gw_subnet_cidr]
}

# ══════════════════════════════════════════════════════════════════════════════
# Aviatrix VPN Gateway
# ══════════════════════════════════════════════════════════════════════════════

resource "aviatrix_gateway" "vpn" {
  cloud_type   = 8 # Azure
  account_name = var.avx_account_name
  gw_name      = "${var.avx_vpn_gw_name}-${local.suffix}"

  # Azure VPC ID format: <vnet_name>:<resource_group>:<vnet_guid>
  vpc_id  = "${local.vnet_name}:${local.vnet_resource_group}:${data.azurerm_virtual_network.foundry.guid}"
  vpc_reg = data.azurerm_location.current.display_name
  subnet  = azurerm_subnet.vpn_gw.address_prefixes[0]
  gw_size = var.avx_vpn_gw_size

  # P2S VPN with NAT and split tunnel
  vpn_access       = true
  vpn_cidr         = var.vpn_client_cidr
  enable_vpn_nat   = true
  split_tunnel     = true
  additional_cidrs = var.foundry_vnet_cidr
  tags             = local.tags

  depends_on = [azurerm_subnet.vpn_gw]
}

# ══════════════════════════════════════════════════════════════════════════════
# VPN User
# ══════════════════════════════════════════════════════════════════════════════

resource "aviatrix_vpn_user" "foundry_user" {
  vpc_id     = aviatrix_gateway.vpn.vpc_id
  gw_name    = aviatrix_gateway.vpn.gw_name
  user_name  = "foundry-user-${local.suffix}"
  user_email = var.vpn_user_email
}
