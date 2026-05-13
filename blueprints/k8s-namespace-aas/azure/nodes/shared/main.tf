#####################
# Pattern B: Namespace-as-a-Service — Azure Node Layer (Layer 3)
#
# Provisions:
#   - User node pool (inline azurerm_kubernetes_cluster_node_pool)
#   - Aviatrix Cluster onboarding + k8s-firewall Helm CRDs
#   - CoreDNS configuration for Azure Private DNS resolution
#   - NGINX Ingress Controller + ExternalDNS via helm.tf
#
# This layer runs AFTER:
#   - Layer 1 (network/) — VNet, Aviatrix transit/spoke, Private DNS
#   - Layer 2 (clusters/) — AKS control plane, Workload Identity setup
#
# Refactored to inline azurerm_kubernetes_cluster_node_pool — the previously
# referenced module ../../../../azure-aks-multicluster/modules/aks-node-group
# does not exist.
#####################

provider "azurerm" {
  features {}
}

provider "aviatrix" {
  controller_ip           = var.controller_ip
  username                = var.controller_username
  password                = var.controller_password
  skip_version_validation = true
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "az"
    args = [
      "aks", "get-credentials",
      "--resource-group", data.terraform_remote_state.network.outputs.shared_resource_group_name,
      "--name", data.terraform_remote_state.cluster.outputs.cluster_name,
      "--format", "exec-credential"
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "az"
      args = [
        "aks", "get-credentials",
        "--resource-group", data.terraform_remote_state.network.outputs.shared_resource_group_name,
        "--name", data.terraform_remote_state.cluster.outputs.cluster_name,
        "--format", "exec-credential"
      ]
    }
  }
}

#####################
# Aviatrix Kubernetes Cluster Onboarding
#####################

resource "aviatrix_kubernetes_cluster" "this" {
  cluster_id          = data.terraform_remote_state.cluster.outputs.cluster_id
  use_csp_credentials = true
}

#####################
# Aviatrix k8s-firewall (CRDs)
#
# Installs FirewallPolicy and WebGroupPolicy CRDs for in-cluster DCF controls.
# CRD-managed policies fill priority 70-99 (team self-service).
#####################

resource "helm_release" "k8s_firewall" {
  name       = "k8s-firewall"
  repository = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart      = "k8s-firewall"
  namespace  = "default"

  wait          = false
  recreate_pods = false

  depends_on = [azurerm_kubernetes_cluster_node_pool.shared]
}

#####################
# User Node Pool
#
# Single shared node pool for all team namespaces.
# Azure CNI Overlay handles pod networking transparently — pods get IPs from
# the overlay CIDR (100.64.0.0/16) without needing per-AZ subnet mappings.
#####################

resource "azurerm_kubernetes_cluster_node_pool" "shared" {
  name                  = "shared"
  kubernetes_cluster_id = data.terraform_remote_state.cluster.outputs.cluster_id

  vm_size              = var.node_pool_config.vm_size
  node_count           = var.node_pool_config.node_count
  min_count            = var.node_pool_config.min_count
  max_count            = var.node_pool_config.max_count
  auto_scaling_enabled = true
  priority             = var.node_pool_config.priority
  eviction_policy      = var.node_pool_config.priority == "Spot" ? "Delete" : null
  spot_max_price       = var.node_pool_config.priority == "Spot" ? -1 : null

  vnet_subnet_id = data.terraform_remote_state.network.outputs.shared_aks_system_subnet_id

  node_labels = {
    "nodepool-type" = "shared"
    "pattern"       = "namespace-aas"
  }

  tags = {
    Environment = "prod"
    Pattern     = "namespace-aas"
    Terraform   = "true"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

#####################
# CoreDNS ConfigMap Patch
#
# Configure CoreDNS to forward queries for the private DNS zone to Azure DNS (168.63.129.16).
# AKS manages CoreDNS as a system addon — we patch rather than replace.
#####################

resource "kubernetes_config_map_v1_data" "coredns_custom" {
  metadata {
    name      = "coredns-custom"
    namespace = "kube-system"
  }

  data = {
    "private-dns.server" = <<-EOF
      ${data.terraform_remote_state.network.outputs.private_dns_zone_name}:53 {
          forward . 168.63.129.16
          cache 30
          log
          errors
      }
    EOF
  }

  force = true

  depends_on = [azurerm_kubernetes_cluster_node_pool.shared]
}
