locals {
  rg_name   = "${var.name}-rg"
  vnet_name = "${var.name}-vnet"

  # Subnet layout carved from the /23 vnet_cidr:
  #   gateway: cidrsubnet(x,5,0) = first /28   (Aviatrix spoke gateway)
  #   ingress: cidrsubnet(x,2,1) = second /25  (internal NGINX LB)
  #   node:    cidrsubnet(x,1,1) = second /24  (AKS node pool)
  gateway_subnet = cidrsubnet(var.vnet_cidr, 5, 0)
  ingress_subnet = cidrsubnet(var.vnet_cidr, 2, 1)
  node_subnet    = cidrsubnet(var.vnet_cidr, 1, 1)
}

resource "azurerm_resource_group" "this" {
  name     = local.rg_name
  location = var.azure_region
  tags     = merge(var.tags, { Name = local.rg_name })
}

resource "azurerm_virtual_network" "this" {
  name                = local.vnet_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr, var.pod_cidr]
  tags                = merge(var.tags, { Name = local.vnet_name, Cluster = var.cluster_name })
}

resource "azurerm_subnet" "gateway" {
  name                 = "${var.name}-avx-gw"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.gateway_subnet]
}

resource "azurerm_subnet" "ingress" {
  name                 = "${var.name}-ingress"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.ingress_subnet]
}

resource "azurerm_subnet" "node" {
  name                 = "${var.name}-node"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.node_subnet]
}

resource "azurerm_subnet" "pod" {
  name                 = "${var.name}-pod"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.pod_cidr]

  # AKS attaches a Microsoft.ContainerService/managedClusters delegation in
  # pod-subnet mode. Ignore it so later applies don't try to remove it (which
  # Azure rejects with SubnetMissingRequiredDelegation while AKS holds the link).
  lifecycle {
    ignore_changes = [delegation]
  }
}

# Route tables. The Aviatrix controller programs 0/0 -> spoke GW on the node and
# pod tables (selected via mc-spoke private_route_table_config). All tables ignore
# route changes so controller-programmed routes survive terraform apply.
resource "azurerm_route_table" "gateway" {
  name                = "${var.name}-gateway-rt"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
  lifecycle {
    ignore_changes = [route]
  }
}

resource "azurerm_route_table" "ingress" {
  name                = "${var.name}-ingress-rt"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
  lifecycle {
    ignore_changes = [route]
  }
}

resource "azurerm_route_table" "node" {
  name                = "${var.name}-node-rt"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
  lifecycle {
    ignore_changes = [route]
  }
}

resource "azurerm_route_table" "pod" {
  name                = "${var.name}-pod-rt"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
  lifecycle {
    ignore_changes = [route]
  }
}

resource "azurerm_subnet_route_table_association" "gateway" {
  subnet_id      = azurerm_subnet.gateway.id
  route_table_id = azurerm_route_table.gateway.id
}

resource "azurerm_subnet_route_table_association" "ingress" {
  subnet_id      = azurerm_subnet.ingress.id
  route_table_id = azurerm_route_table.ingress.id
}

resource "azurerm_subnet_route_table_association" "node" {
  subnet_id      = azurerm_subnet.node.id
  route_table_id = azurerm_route_table.node.id
}

resource "azurerm_subnet_route_table_association" "pod" {
  subnet_id      = azurerm_subnet.pod.id
  route_table_id = azurerm_route_table.pod.id
}

module "spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "9.0.0"

  cloud            = "Azure"
  name             = var.name
  region           = var.aviatrix_azure_region
  account          = var.aviatrix_azure_account_name
  use_existing_vpc = true
  vpc_id           = format("%s:%s:%s", azurerm_virtual_network.this.name, azurerm_resource_group.this.name, azurerm_virtual_network.this.guid)
  gw_subnet        = azurerm_subnet.gateway.address_prefixes[0]
  hagw_subnet      = azurerm_subnet.gateway.address_prefixes[0]
  ha_gw            = false

  single_ip_snat = true
  private_route_table_config = [
    "${azurerm_route_table.node.name}:${azurerm_resource_group.this.name}",
    "${azurerm_route_table.pod.name}:${azurerm_resource_group.this.name}",
  ]

  attached   = var.transit_type == "aviatrix"
  transit_gw = var.transit_type == "aviatrix" ? var.transit_gw_name : ""

  tags = var.tags

  depends_on = [
    azurerm_subnet_route_table_association.node,
    azurerm_subnet_route_table_association.pod,
    azurerm_subnet_route_table_association.gateway,
  ]
}

# Fail fast if attaching to a transit without naming it.
resource "terraform_data" "validate_transit" {
  lifecycle {
    precondition {
      condition     = var.transit_type != "aviatrix" || length(var.transit_gw_name) > 0
      error_message = "transit_gw_name is required when transit_type = aviatrix."
    }
  }
}
