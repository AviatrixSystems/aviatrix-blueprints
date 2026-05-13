# =============================================================================
# Aviatrix Spoke Gateway
# =============================================================================

# Spoke gateway deployed into the VNet's dedicated gateway subnet.
# No transit attachment required: DCF enforces WebGroup egress rules
# directly at the spoke via local egress (single_ip_snat = true).
# single_ip_snat is required for FQDN-based DCF filtering: the gateway
# must SNAT pod traffic to its own EIP so the firewall engine can match
# outbound connections to the correct WebGroup entries.
resource "aviatrix_spoke_gateway" "obot" {
  cloud_type        = 8 # Azure
  account_name      = var.arm_account_name
  gw_name           = "${var.name_prefix}-spoke"
  vpc_id            = "${azurerm_virtual_network.obot.name}:${azurerm_resource_group.obot.name}:${azurerm_virtual_network.obot.guid}"
  vpc_reg           = var.azure_location
  gw_size           = var.spoke_gateway_size
  subnet            = var.spoke_gateway_subnet_cidr
  single_ip_snat    = true
  manage_ha_gateway = false

  depends_on = [
    azurerm_subnet_route_table_association.avx_gateway,
    azurerm_subnet_route_table_association.aks,
  ]
}
