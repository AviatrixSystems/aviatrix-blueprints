#####################
# Pattern B: Namespace-as-a-Service — Azure Node Layer (Layer 3)
#
# Provisions:
#   - User node pool via aks-node-group module
#   - Aviatrix k8s-firewall Helm chart (CRDs for in-cluster DCF policies)
#   - CoreDNS configuration for Azure Private DNS resolution
#   - NGINX Ingress Controller + ExternalDNS via helm.tf
#
# This layer runs AFTER:
#   - Layer 1 (network/) — VNet, Aviatrix transit/spoke, Private DNS
#   - Layer 2 (clusters/) — AKS control plane, Workload Identity setup
#####################

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "aviatrix" {
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
}

#####################
# User Node Pool
#
# Single shared node pool for all team namespaces.
# NOTE: Unlike EKS, AKS does not need ENIConfig resources.
# Azure CNI Overlay handles pod networking transparently — pods get IPs from
# the overlay CIDR (100.64.0.0/16) without needing per-AZ subnet mappings.
#####################

module "shared_node_pool" {
  source = "../../../../azure-aks-multicluster/modules/aks-node-group"

  cluster_name        = data.terraform_remote_state.cluster.outputs.cluster_name
  resource_group_name = data.terraform_remote_state.network.outputs.shared_resource_group_name

  subnet_id = data.terraform_remote_state.network.outputs.shared_aks_system_subnet_id

  node_pool_name = "shared"
  min_count      = var.node_pool_config.min_count
  max_count      = var.node_pool_config.max_count
  node_count     = var.node_pool_config.node_count
  vm_size        = var.node_pool_config.vm_size
  priority       = var.node_pool_config.priority

  node_labels = {
    "nodepool-type" = "shared"
    "pattern"       = "namespace-aas"
  }

  tags = {
    Environment = "prod"
    Pattern     = "namespace-aas"
    Terraform   = "true"
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

  depends_on = [module.shared_node_pool]
}
