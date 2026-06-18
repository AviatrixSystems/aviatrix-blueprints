# VNet vpc_id format for Azure Aviatrix: <vnet_name>:<resource_group>:<vnet_resource_guid>
locals {
  vpc_id = "${azurerm_virtual_network.this.name}:${azurerm_resource_group.this.name}:${azurerm_virtual_network.this.guid}"
}

resource "aviatrix_spoke_gateway" "this" {
  cloud_type     = 8 # Azure
  account_name   = var.aviatrix_account_name
  gw_name        = coalesce(var.spoke_gateway_name, "${local.name_prefix}-spoke-gw")
  vpc_id         = local.vpc_id
  vpc_reg        = data.azurerm_location.this.display_name
  gw_size        = var.spoke_gw_size
  subnet         = var.gw_subnet_cidr
  single_ip_snat = true
  tags           = local.common_tags

  depends_on = [
    azurerm_subnet.gw,
    azurerm_subnet_route_table_association.gw,
    azurerm_subnet_route_table_association.aks,
  ]
}
