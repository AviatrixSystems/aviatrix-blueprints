#####################
# Pattern B: Namespace-as-a-Service — Azure Shared AKS Cluster (Layer 2)
#
# Provisions a single shared AKS cluster. All teams (team-a, team-b, team-c)
# get isolated namespaces within this cluster.
#
# Isolation is enforced by DCF SmartGroups (k8s_namespace type), NOT by RBAC alone.
# RBAC is NOT a hard security boundary — DCF is the primary network isolation.
#
# Authentication:
#   - Aviatrix: AVIATRIX_CONTROLLER_IP, AVIATRIX_USERNAME, AVIATRIX_PASSWORD env vars
#   - Azure: az login or service principal env vars (ARM_*)
#
# Refactored to inline azurerm_kubernetes_cluster — the previously referenced
# module ../../../../azure-aks-multicluster/modules/aks-cluster does not exist.
#####################

provider "azurerm" {
  features {}
  subscription_id = data.terraform_remote_state.network.outputs.azure_subscription_id
}

provider "azuread" {}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.this.kube_config[0].host
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "az"
    args = [
      "aks", "get-credentials",
      "--resource-group", data.terraform_remote_state.network.outputs.shared_resource_group_name,
      "--name", data.terraform_remote_state.network.outputs.shared_cluster_name,
      "--format", "exec-credential"
    ]
  }
}

locals {
  cluster_name        = data.terraform_remote_state.network.outputs.shared_cluster_name
  resource_group_name = data.terraform_remote_state.network.outputs.shared_resource_group_name
  location            = data.terraform_remote_state.network.outputs.azure_region

  common_tags = {
    Environment = "prod"
    Pattern     = "namespace-aas"
    Terraform   = "true"
  }
}

#####################
# User-Assigned Managed Identity for AKS
#####################

resource "azurerm_user_assigned_identity" "aks" {
  name                = "${local.cluster_name}-identity"
  location            = local.location
  resource_group_name = local.resource_group_name
  tags                = local.common_tags
}

resource "azurerm_role_assignment" "aks_vnet_contributor" {
  scope                = data.terraform_remote_state.network.outputs.shared_arm_vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

#####################
# Managed Identities for in-cluster workloads (Workload Identity)
#####################

resource "azurerm_user_assigned_identity" "external_dns" {
  name                = "${local.cluster_name}-external-dns"
  location            = local.location
  resource_group_name = local.resource_group_name
  tags                = local.common_tags
}

resource "azurerm_role_assignment" "external_dns_zone_contributor" {
  scope                = data.terraform_remote_state.network.outputs.private_dns_zone_id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.external_dns.principal_id
}

resource "azurerm_role_assignment" "external_dns_rg_reader" {
  scope                = "/subscriptions/${data.terraform_remote_state.network.outputs.azure_subscription_id}/resourceGroups/${data.terraform_remote_state.network.outputs.private_dns_zone_resource_group}"
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.external_dns.principal_id
}

resource "azurerm_user_assigned_identity" "ingress" {
  name                = "${local.cluster_name}-ingress"
  location            = local.location
  resource_group_name = local.resource_group_name
  tags                = local.common_tags
}

#####################
# Shared AKS Cluster
#
# Azure CNI Overlay: pods get IPs from the overlay CIDR (100.64.0.0/16).
# SNAT happens at the Aviatrix spoke gateway (single_ip_snat = true in network).
#####################

resource "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  location            = local.location
  resource_group_name = local.resource_group_name
  dns_prefix          = local.cluster_name
  kubernetes_version  = var.kubernetes_version

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name                         = "system"
    vm_size                      = "Standard_B2s"
    node_count                   = 1
    min_count                    = 1
    max_count                    = 3
    auto_scaling_enabled         = true
    vnet_subnet_id               = data.terraform_remote_state.network.outputs.shared_aks_system_subnet_id
    max_pods                     = 110
    only_critical_addons_enabled = true

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
    pod_cidr            = data.terraform_remote_state.network.outputs.pod_cidr
  }

  depends_on = [
    azurerm_role_assignment.aks_vnet_contributor,
  ]

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }

  tags = local.common_tags
}

#####################
# Workload Identity Federated Credentials
#####################

resource "azurerm_federated_identity_credential" "external_dns" {
  name                = "${local.cluster_name}-external-dns"
  resource_group_name = local.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.this.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.external_dns.id
  subject             = "system:serviceaccount:kube-system:external-dns"
}

resource "azurerm_federated_identity_credential" "ingress" {
  name                = "${local.cluster_name}-ingress"
  resource_group_name = local.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.this.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.ingress.id
  subject             = "system:serviceaccount:kube-system:ingress-nginx"
}
