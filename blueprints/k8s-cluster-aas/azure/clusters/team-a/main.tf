#####################
# AKS Cluster Layer (Layer 2) - Team-A
#
# Provisions the AKS control plane using outputs from the network layer.
# Node pools are managed separately in Layer 3 (nodes/).
# Each team is cluster-admin in their own cluster (Pattern A isolation).
#
# NOTE: This file was refactored to use inline azurerm_kubernetes_cluster
# resources (instead of a shared module) — the original module path
# ../../../../azure-aks-multicluster/modules/aks-cluster does not exist.
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
      "--resource-group", data.terraform_remote_state.network.outputs.team_a_resource_group_name,
      "--name", data.terraform_remote_state.network.outputs.team_a_cluster_name,
      "--format", "exec-credential"
    ]
  }
}

locals {
  cluster_name        = data.terraform_remote_state.network.outputs.team_a_cluster_name
  resource_group_name = data.terraform_remote_state.network.outputs.team_a_resource_group_name
  location            = data.terraform_remote_state.network.outputs.azure_region

  common_tags = {
    Environment = "demo"
    Team        = "team-a"
    Terraform   = "true"
    Pattern     = "cluster-aas"
  }
}

#####################
# User-Assigned Managed Identity for the AKS control plane
#####################

resource "azurerm_user_assigned_identity" "aks" {
  name                = "${local.cluster_name}-identity"
  location            = local.location
  resource_group_name = local.resource_group_name
  tags                = local.common_tags
}

# AKS identity needs Network Contributor on the team VNet so it can manage
# load balancers / NICs in the AKS subnets. (Route tables are owned by the
# Aviatrix spoke gateway, so we don't grant a separate role on those.)
resource "azurerm_role_assignment" "aks_vnet_contributor" {
  scope                = data.terraform_remote_state.network.outputs.team_a_arm_vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

#####################
# Managed Identities for in-cluster workloads (Workload Identity)
#####################

# ExternalDNS — writes records into the Azure Private DNS zone.
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

# NGINX Ingress Controller — needs to read/manage internal load balancers
# in the AKS subnet. Workload-identity-annotated on the ingress-nginx SA.
resource "azurerm_user_assigned_identity" "ingress" {
  name                = "${local.cluster_name}-ingress"
  location            = local.location
  resource_group_name = local.resource_group_name
  tags                = local.common_tags
}

#####################
# AKS Cluster
#
# Azure CNI Overlay: pod IPs come from the overlay pod_cidr (100.64.0.0/16,
# overlapping across team VNets) — NOT from a VNet subnet. Egress SNAT is
# performed at the Aviatrix spoke gateway (single_ip_snat in the network
# layer), so we do NOT set outbound_type = "userDefinedRouting" here.
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
    vm_size                      = var.system_node_vm_size
    node_count                   = 1
    min_count                    = 1
    max_count                    = 3
    auto_scaling_enabled         = true
    vnet_subnet_id               = data.terraform_remote_state.network.outputs.team_a_aks_system_subnet_id
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
# Bind in-cluster ServiceAccounts to the managed identities created above.
# Must be created after the cluster (needs OIDC issuer URL).
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
