# VNet vpc_id format: <vnet_name>:<resource_group>:<vnet_resource_guid>
locals {
  vpc_id = "${azurerm_virtual_network.runner.name}:${azurerm_resource_group.runner.name}:${azurerm_virtual_network.runner.guid}"
}

resource "aviatrix_spoke_gateway" "runner" {
  cloud_type     = 8
  account_name   = var.aviatrix_account_name
  gw_name        = coalesce(var.spoke_gateway_name, "${local.name_prefix}-spoke-gw")
  vpc_id         = local.vpc_id
  vpc_reg        = data.azurerm_location.this.display_name
  gw_size        = "Standard_B2ms"
  subnet         = var.gw_subnet_cidr
  single_ip_snat = true
  tags           = local.common_tags

  # Aviatrix 9.0: with single_ip_snat=true, controller programs listed private
  # RTs to route 0.0.0.0/0 via the spoke GW's ENI. Format: "<rt_name>:<rg_name>".
  private_route_table_config = [
    "${azurerm_route_table.runner.name}:${azurerm_resource_group.runner.name}",
  ]

  depends_on = [
    azurerm_subnet.gw,
    azurerm_subnet_route_table_association.gw,
    azurerm_subnet_route_table_association.runner,
  ]
}
