resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name_prefix}-spoke"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${local.name_prefix}-spoke"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = local.common_tags
}

# Public RT for the Aviatrix spoke gateway subnet — explicit default-internet
# satisfies the controller's preflight (AVXERR-TRANSIT-0067) and lets the GW
# reach the controller / internet directly.
resource "azurerm_route_table" "gw" {
  name                = "rt-${local.name_prefix}-gw"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  route {
    name           = "default-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }

  lifecycle {
    ignore_changes = [route]
  }
}

# AKS RT — default route to None signals private subnet to Aviatrix 8.2 preflight.
# single_ip_snat replaces None with VirtualAppliance → spoke GW ENI after GW comes up.
# AKS cluster depends_on spoke GW so the route is already VirtualAppliance by the time
# AKS validates the RT.
resource "azurerm_route_table" "aks" {
  name                = "rt-${local.name_prefix}-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  route {
    name           = "default-none"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }

  lifecycle {
    ignore_changes = [route]
  }
}

resource "azurerm_subnet" "gw" {
  name                 = "${local.name_prefix}-gw-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.gw_subnet_cidr]
}

resource "azurerm_subnet" "aks" {
  name                 = "${local.name_prefix}-aks-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.aks_subnet_cidr]

  # No outbound NAT — egress goes via Aviatrix spoke gateway (SNAT to spoke eip).
  default_outbound_access_enabled = false
}

resource "azurerm_subnet_route_table_association" "gw" {
  subnet_id      = azurerm_subnet.gw.id
  route_table_id = azurerm_route_table.gw.id
}

resource "azurerm_subnet_route_table_association" "aks" {
  subnet_id      = azurerm_subnet.aks.id
  route_table_id = azurerm_route_table.aks.id
}
