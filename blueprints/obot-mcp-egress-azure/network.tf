# =============================================================================
# Network: Aviatrix spoke gateway subnet + route tables
# =============================================================================

# Dedicated subnet for the Aviatrix spoke gateway.
# Must not overlap with var.aks_subnet_cidr.
resource "azurerm_subnet" "avx_gateway" {
  name                 = "${var.name_prefix}-sn-avx-gw"
  address_prefixes     = [var.spoke_gateway_subnet_cidr]
  resource_group_name  = azurerm_resource_group.obot.name
  virtual_network_name = azurerm_virtual_network.obot.name
}

# Public route table for the gateway subnet.
# next_hop_type = "Internet" classifies the subnet as public to Aviatrix,
# required for the spoke gateway to acquire an EIP and handle local egress.
resource "azurerm_route_table" "avx_gateway" {
  name                = "${var.name_prefix}-rt-avx-gw"
  location            = var.azure_location
  resource_group_name = azurerm_resource_group.obot.name

  route {
    name           = "default-Internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }

  lifecycle {
    # Aviatrix injects additional routes during gateway provisioning.
    ignore_changes = [route, tags]
  }
}

resource "azurerm_subnet_route_table_association" "avx_gateway" {
  subnet_id      = azurerm_subnet.avx_gateway.id
  route_table_id = azurerm_route_table.avx_gateway.id
}

# Private route table for the AKS node subnet.
# next_hop_type = "None" marks the subnet as private. Aviatrix replaces the
# default route with its spoke gateway, so all pod egress flows through DCF.
#
# WARNING: Applying this association redirects all pod outbound traffic through
# the Aviatrix spoke gateway. Verify the DCF infrastructure permits in dcf.tf
# match your cluster's essential egress domains before applying to production.
resource "azurerm_route_table" "aks" {
  name                = "${var.name_prefix}-rt-aks"
  location            = var.azure_location
  resource_group_name = azurerm_resource_group.obot.name

  route {
    name           = "blackhole"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }

  lifecycle {
    # Aviatrix modifies routes during gateway provisioning.
    ignore_changes = [route, tags]
  }
}

# AKS nodes need outbound internet during bootstrap (package downloads).
# Associate the blackhole RT only after AKS reports healthy to prevent
# nodes being cut off before they finish bootstrapping.
resource "azurerm_subnet_route_table_association" "aks" {
  subnet_id      = azurerm_subnet.aks_nodes.id
  route_table_id = azurerm_route_table.aks.id

  depends_on = [azurerm_kubernetes_cluster.obot]
}
