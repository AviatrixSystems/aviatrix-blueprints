terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  cluster_name = data.terraform_remote_state.network.outputs.backend_cluster_name
  rg_name      = data.terraform_remote_state.network.outputs.backend_resource_group_name
  name_prefix  = data.terraform_remote_state.network.outputs.name_prefix
}

#####################
# User-Assigned Managed Identity for AKS
#####################

resource "azurerm_user_assigned_identity" "aks" {
  name                = "${local.cluster_name}-identity"
  location            = var.azure_region
  resource_group_name = local.rg_name
}

resource "azurerm_role_assignment" "aks_vnet_contributor" {
  scope                = data.terraform_remote_state.network.outputs.backend_vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_role_assignment" "aks_route_table" {
  scope                = data.terraform_remote_state.network.outputs.backend_route_table_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

#####################
# ExternalDNS Managed Identity (Workload Identity)
#####################

resource "azurerm_user_assigned_identity" "external_dns" {
  name                = "${local.cluster_name}-external-dns"
  location            = var.azure_region
  resource_group_name = local.rg_name
}

resource "azurerm_role_assignment" "external_dns_zone_contributor" {
  scope                = data.terraform_remote_state.network.outputs.private_dns_zone_id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.external_dns.principal_id
}

resource "azurerm_role_assignment" "external_dns_rg_reader" {
  scope                = data.terraform_remote_state.network.outputs.backend_resource_group_id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.external_dns.principal_id
}

#####################
# AKS Cluster
#####################

resource "azurerm_kubernetes_cluster" "aks" {
  name                = local.cluster_name
  location            = var.azure_region
  resource_group_name = local.rg_name
  dns_prefix          = local.cluster_name
  kubernetes_version  = var.kubernetes_version

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name                 = "system"
    vm_size              = var.node_pool_config.vm_size
    node_count           = var.node_pool_config.node_count
    min_count            = var.node_pool_config.min_count
    max_count            = var.node_pool_config.max_count
    auto_scaling_enabled = true
    vnet_subnet_id       = data.terraform_remote_state.network.outputs.backend_nodes_subnet_id

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
    network_policy      = "cilium" # Activates Azure CNI Powered by Cilium (replaces kube-proxy with eBPF)

    pod_cidr = data.terraform_remote_state.network.outputs.pod_cidr

    service_cidr   = data.terraform_remote_state.network.outputs.service_cidr
    dns_service_ip = data.terraform_remote_state.network.outputs.dns_service_ip

    outbound_type = "userDefinedRouting"
  }

  # The spoke GW's public IP is auto-included because AKS nodes egress through
  # it (UDR 0.0.0.0/0 → spoke GW → SNAT → public IP). Without this the kubelet
  # CSE step fails with VMExtensionError_K8SAPIServerConnFail.
  api_server_access_profile {
    authorized_ip_ranges = concat(
      var.authorized_ip_ranges,
      ["${data.terraform_remote_state.network.outputs.backend_spoke_gateway_public_ip}/32"],
    )
  }

  depends_on = [
    azurerm_role_assignment.aks_vnet_contributor,
    azurerm_role_assignment.aks_route_table,
  ]
}

resource "azurerm_federated_identity_credential" "external_dns" {
  name                = "external-dns"
  resource_group_name = local.rg_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.external_dns.id
  subject             = "system:serviceaccount:kube-system:external-dns"
}
