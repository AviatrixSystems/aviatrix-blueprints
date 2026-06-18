resource "azurerm_resource_group" "runner" {
  name     = "rg-${local.name_prefix}-spoke"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "runner" {
  name                = "vnet-${local.name_prefix}-spoke"
  location            = azurerm_resource_group.runner.location
  resource_group_name = azurerm_resource_group.runner.name
  address_space       = [var.vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_route_table" "gw" {
  name                = "rt-${local.name_prefix}-gw"
  location            = azurerm_resource_group.runner.location
  resource_group_name = azurerm_resource_group.runner.name
  tags                = local.common_tags

  route {
    name           = "default-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }
}

# Private RT for the runner subnet — empty at create time. Aviatrix 9.0
# programs 0.0.0.0/0 → spoke GW ENI via private_route_table_config on the
# spoke resource. ignore_changes prevents Terraform from reverting that
# out-of-band route update on subsequent applies.
resource "azurerm_route_table" "runner" {
  name                = "rt-${local.name_prefix}"
  location            = azurerm_resource_group.runner.location
  resource_group_name = azurerm_resource_group.runner.name
  tags                = local.common_tags

  lifecycle {
    ignore_changes = [route]
  }
}

resource "azurerm_subnet" "gw" {
  name                 = "${local.name_prefix}-gw-subnet"
  resource_group_name  = azurerm_resource_group.runner.name
  virtual_network_name = azurerm_virtual_network.runner.name
  address_prefixes     = [var.gw_subnet_cidr]
}

resource "azurerm_subnet" "runner" {
  name                 = "${local.name_prefix}-subnet"
  resource_group_name  = azurerm_resource_group.runner.name
  virtual_network_name = azurerm_virtual_network.runner.name
  address_prefixes     = [var.runner_subnet_cidr]

  default_outbound_access_enabled = false
}

resource "azurerm_subnet_route_table_association" "gw" {
  subnet_id      = azurerm_subnet.gw.id
  route_table_id = azurerm_route_table.gw.id
}

resource "azurerm_subnet_route_table_association" "runner" {
  subnet_id      = azurerm_subnet.runner.id
  route_table_id = azurerm_route_table.runner.id
}
