# =============================================================================
# Azure Resource Group, VNet, AKS Cluster
# =============================================================================

resource "azurerm_resource_group" "obot" {
  name     = var.resource_group_name
  location = var.azure_location
}

resource "azurerm_virtual_network" "obot" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.obot.location
  resource_group_name = azurerm_resource_group.obot.name
  address_space       = [var.vnet_address_space]
}

# AKS node subnet. Azure CNI required: pods get VNet IPs directly.
# Without Azure CNI, SmartGroups cannot resolve pod IPs and
# FirewallPolicy CRDs will never match traffic at the spoke gateway.
resource "azurerm_subnet" "aks_nodes" {
  name                 = "${var.name_prefix}-sn-aks"
  address_prefixes     = [var.aks_subnet_cidr]
  resource_group_name  = azurerm_resource_group.obot.name
  virtual_network_name = azurerm_virtual_network.obot.name

  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_kubernetes_cluster" "obot" {
  name                              = "${var.name_prefix}-aks"
  location                          = azurerm_resource_group.obot.location
  resource_group_name               = azurerm_resource_group.obot.name
  node_resource_group               = "${var.name_prefix}-aksnode-rg"
  dns_prefix                        = "${var.name_prefix}-aks"
  local_account_disabled            = false
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name           = "agentpool"
    vm_size        = var.aks_vm_size
    node_count     = var.aks_node_count
    vnet_subnet_id = azurerm_subnet.aks_nodes.id

    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = var.aks_service_cidr
    dns_service_ip    = var.aks_dns_service_ip
  }
}

resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_resource_group.obot.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.obot.identity[0].principal_id
}
