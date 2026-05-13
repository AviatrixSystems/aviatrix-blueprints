# -----------------------------------------------------------------------------
# Pattern C: AKS Non-Production Cluster
# Dedicated non-production cluster in isolated VNet
# Azure CNI Overlay + Workload Identity
#
# Refactored to inline azurerm_kubernetes_cluster — the previously referenced
# module ../../../../azure-aks-multicluster/modules/aks-cluster does not exist.
# -----------------------------------------------------------------------------

provider "azurerm" {
  features {}
}

locals {
  cluster_name = "${data.terraform_remote_state.network.outputs.name_prefix}-nonprod"

  common_tags = {
    Environment = "non-production"
    Pattern     = "C"
    ManagedBy   = "terraform"
  }
}

resource "azurerm_user_assigned_identity" "aks" {
  name                = "${local.cluster_name}-identity"
  location            = var.azure_region
  resource_group_name = var.resource_group_name
  tags                = local.common_tags
}

resource "azurerm_role_assignment" "aks_vnet_contributor" {
  scope                = var.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  location            = var.azure_region
  resource_group_name = var.resource_group_name
  dns_prefix          = local.cluster_name
  kubernetes_version  = var.kubernetes_version

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name                 = "system"
    vm_size              = var.node_vm_size
    auto_scaling_enabled = true
    min_count            = var.node_min_count
    max_count            = var.node_max_count
    os_disk_size_gb      = 100
    vnet_subnet_id       = var.subnet_id
    node_labels = {
      "environment" = "non-production"
      "cluster"     = "nonprod"
    }

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = var.pod_cidr
  }

  depends_on = [
    azurerm_role_assignment.aks_vnet_contributor,
  ]

  tags = local.common_tags
}
