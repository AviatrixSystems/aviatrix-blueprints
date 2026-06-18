locals {
  # VNet has TWO address spaces:
  #   - Routable /23 (per-cluster unique, e.g. 10.10.0.0/23 for frontend) — node + system + Aviatrix GW subnets
  #   - Pod CIDR /16 (e.g., 100.64.0.0/16) — added as a 2nd VNet address space, carved into a single
  #     "podsubnet" used by AKS pod-subnet mode. Both clusters use the same pod CIDR (overlapping by
  #     design); VNets are isolated, and the Aviatrix spoke GW SNATs pod CIDR before transit.
  #
  # Routable subnet layout:
  #   avx-gw:  10.x.0.0/28    (Aviatrix spoke gateway — 11 usable IPs)
  #   system:  10.x.0.128/25  (Internal LBs, ingress — 123 usable IPs)
  #   nodes:   10.x.1.0/24    (AKS node pool VMs — 251 usable IPs)
  # Pod subnet:
  #   pods:    100.64.0.0/16  (AKS pods — 65k IPs, full pod address space)

  rg_name   = "${var.name_prefix}-${var.name}-rg"
  vnet_name = "${var.name_prefix}-${var.name}-vnet"

  # Derive subnet CIDRs from the /23 VNet CIDR deterministically using cidrsubnet().
  # Example layout for 10.10.0.0/23:
  #   avx_gw_subnet : cidrsubnet(x, 5, 0) = 10.10.0.0/28   (first /28  — 11 usable)
  #   system_subnet : cidrsubnet(x, 2, 1) = 10.10.0.128/25 (second /25 — 123 usable)
  #   nodes_subnet  : cidrsubnet(x, 1, 1) = 10.10.1.0/24   (second /24 — 251 usable)
  # No overlap between these three ranges.
  avx_gw_subnet = cidrsubnet(var.vnet_cidr, 5, 0) # /28 — Aviatrix spoke gateway
  system_subnet = cidrsubnet(var.vnet_cidr, 2, 1) # /25 — internal LBs / ingress
  nodes_subnet  = cidrsubnet(var.vnet_cidr, 1, 1) # /24 — AKS node pool
}

resource "azurerm_resource_group" "vnet" {
  name     = local.rg_name
  location = var.region
  tags     = merge(var.tags, { Name = local.rg_name })
}

resource "azurerm_virtual_network" "vnet" {
  name                = local.vnet_name
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name
  address_space       = [var.vnet_cidr, var.pod_cidr]
  tags                = merge(var.tags, { Name = local.vnet_name, Cluster = var.cluster_name })
}

# Aviatrix spoke gateway subnet — dedicated /28
resource "azurerm_subnet" "avx_gw" {
  name                 = "${var.name}-avx-gw"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.avx_gw_subnet]
}

# System subnet — internal load balancers, ingress
resource "azurerm_subnet" "system" {
  name                 = "${var.name}-system"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.system_subnet]
}

# Node subnet — AKS node pool VMs
# Route table association (UDR → Aviatrix) is done in the parent module after the spoke GW is created
resource "azurerm_subnet" "nodes" {
  name                 = "${var.name}-nodes"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [local.nodes_subnet]
}

# Pod subnet — AKS allocates pod IPs from here in pod-subnet mode (NOT overlay).
# Pod CIDR is the entire 2nd VNet address space; no further sub-carving needed because
# (a) pods don't share this subnet with other resources and (b) max 65k IPs covers any
# realistic node-pool scale. Route table association (UDR → Aviatrix) is done in the
# parent module so pod egress flows through the spoke GW for SNAT + DCF inspection.
resource "azurerm_subnet" "pods" {
  name                 = "${var.name}-pods"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.pod_cidr]

  # AKS auto-attaches a Microsoft.ContainerService/managedClusters delegation when the
  # cluster comes up in pod-subnet mode. Without this, every subsequent apply on the
  # network layer plans to remove that delegation and Azure rejects with
  # SubnetMissingRequiredDelegation while AKS holds the serviceAssociationLink.
  lifecycle {
    ignore_changes = [delegation]
  }
}
