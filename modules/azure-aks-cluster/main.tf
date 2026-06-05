# User-assigned managed identity for the AKS control plane.
resource "azurerm_user_assigned_identity" "aks" {
  name                = "${var.cluster_name}-identity"
  location            = var.azure_region
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "aks_vnet_contributor" {
  scope                = var.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_role_assignment" "aks_node_rt" {
  scope                = var.node_route_table_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_role_assignment" "aks_pod_rt" {
  scope                = var.pod_route_table_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = var.azure_region
  resource_group_name = var.resource_group_name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  tags                = var.tags

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name                 = "system"
    vm_size              = var.node_pool_config.vm_size
    node_count           = var.node_pool_config.node_count
    min_count            = var.node_pool_config.min_count
    max_count            = var.node_pool_config.max_count
    auto_scaling_enabled = true
    vnet_subnet_id       = var.node_subnet_id
    pod_subnet_id        = var.pod_subnet_id
    max_pods             = 250

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin     = "azure"
    network_policy     = "cilium"
    network_data_plane = "cilium"
    service_cidr       = var.service_cidr
    dns_service_ip     = var.dns_service_ip
    # All egress routes through the Aviatrix spoke gateway via the controller-
    # programmed 0/0 route on the node + pod route tables (network layer).
    outbound_type = "userDefinedRouting"
  }

  api_server_access_profile {
    authorized_ip_ranges = concat(
      var.authorized_ip_ranges,
      ["${var.spoke_gateway_public_ip}/32"],
      var.enable_aviatrix_onboarding && var.aviatrix_controller_public_ip != null
      ? ["${var.aviatrix_controller_public_ip}/32"]
      : [],
    )
  }

  depends_on = [
    azurerm_role_assignment.aks_vnet_contributor,
    azurerm_role_assignment.aks_node_rt,
    azurerm_role_assignment.aks_pod_rt,
  ]

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }
}
