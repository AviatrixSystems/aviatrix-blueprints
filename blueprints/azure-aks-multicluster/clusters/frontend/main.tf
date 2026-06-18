terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "aviatrix" {
  controller_ip           = var.aviatrix_controller_ip
  username                = var.aviatrix_username
  password                = var.aviatrix_password
  skip_version_validation = true
}

locals {
  cluster_name = data.terraform_remote_state.network.outputs.frontend_cluster_name
  rg_name      = data.terraform_remote_state.network.outputs.frontend_resource_group_name
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

# AKS identity needs Network Contributor on the VNet to manage NICs and load balancers
resource "azurerm_role_assignment" "aks_vnet_contributor" {
  scope                = data.terraform_remote_state.network.outputs.frontend_vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# AKS identity needs to read/write the UDR route table
resource "azurerm_role_assignment" "aks_route_table" {
  scope                = data.terraform_remote_state.network.outputs.frontend_route_table_id
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

# ExternalDNS needs to manage records in the private DNS zone
resource "azurerm_role_assignment" "external_dns_zone_contributor" {
  scope                = data.terraform_remote_state.network.outputs.private_dns_zone_id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.external_dns.principal_id
}

# ExternalDNS also needs Reader on the resource group that contains the DNS zone
resource "azurerm_role_assignment" "external_dns_rg_reader" {
  scope                = data.terraform_remote_state.network.outputs.frontend_resource_group_id
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

  # Enable OIDC issuer for Workload Identity (Azure equivalent of IRSA)
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name                 = "system"
    vm_size              = var.node_pool_config.vm_size
    node_count           = var.node_pool_config.node_count
    min_count            = var.node_pool_config.min_count
    max_count            = var.node_pool_config.max_count
    auto_scaling_enabled = true
    vnet_subnet_id       = data.terraform_remote_state.network.outputs.frontend_nodes_subnet_id
    # Pod-subnet mode: pod IPs come from a dedicated VNet subnet (100.64.0.0/16),
    # NOT from a Cilium overlay. Pods get real VNet addresses → Azure routes them
    # natively → packets reach the Aviatrix spoke GW with their original pod IP.
    pod_subnet_id = data.terraform_remote_state.network.outputs.frontend_pod_subnet_id
    max_pods      = 250

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
    network_policy     = "cilium" # Activates Azure CNI Powered by Cilium (replaces kube-proxy with eBPF)
    network_data_plane = "cilium" # Required by AKS API alongside network_policy=cilium

    # No network_plugin_mode — pods use the dedicated pod_subnet_id on the node pool.
    # Pod IPs are real VNet addresses (from 100.64.0.0/16, the 2nd VNet address space),
    # so Azure does NOT perform node-level SNAT. Pod packets traverse the Azure VNet
    # natively to the Aviatrix spoke GW where customized_snat fires after DCF inspection.

    service_cidr   = data.terraform_remote_state.network.outputs.service_cidr
    dns_service_ip = data.terraform_remote_state.network.outputs.dns_service_ip

    # All egress routes through the Aviatrix spoke gateway via the UDR
    # pre-associated with the nodes AND pod subnets in the network layer.
    outbound_type = "userDefinedRouting"
  }

  # The spoke GW's public IP is auto-included because AKS nodes egress through
  # it (UDR 0.0.0.0/0 → spoke GW → SNAT → public IP). Without this the kubelet
  # CSE step fails with VMExtensionError_K8SAPIServerConnFail.
  # The Aviatrix Controller's egress IP is appended when onboarding is enabled
  # so the controller can reach the API server after fetching the kubeconfig.
  api_server_access_profile {
    authorized_ip_ranges = concat(
      var.authorized_ip_ranges,
      ["${data.terraform_remote_state.network.outputs.frontend_spoke_gateway_public_ip}/32"],
      var.enable_aviatrix_onboarding && var.aviatrix_controller_public_ip != null
      ? ["${var.aviatrix_controller_public_ip}/32"]
      : [],
    )
  }

  depends_on = [
    azurerm_role_assignment.aks_vnet_contributor,
    azurerm_role_assignment.aks_route_table,
  ]

  # node_count in the default_node_pool is autoscaled — ignore drift between
  # the tfvars seed value and the live count to keep terraform plan idempotent.
  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }
}

#####################
# ExternalDNS Federated Identity Credential
# Binds the ExternalDNS K8s ServiceAccount to the Azure managed identity.
# Must be created after the cluster (needs OIDC issuer URL).
#####################

resource "azurerm_federated_identity_credential" "external_dns" {
  name                = "external-dns"
  resource_group_name = local.rg_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.external_dns.id
  subject             = "system:serviceaccount:kube-system:external-dns"
}
