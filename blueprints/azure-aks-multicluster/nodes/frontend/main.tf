terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.cluster.outputs.host
  client_certificate     = data.terraform_remote_state.cluster.outputs.client_certificate
  client_key             = data.terraform_remote_state.cluster.outputs.client_key
  cluster_ca_certificate = data.terraform_remote_state.cluster.outputs.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.cluster.outputs.host
    client_certificate     = data.terraform_remote_state.cluster.outputs.client_certificate
    client_key             = data.terraform_remote_state.cluster.outputs.client_key
    cluster_ca_certificate = data.terraform_remote_state.cluster.outputs.cluster_ca_certificate
  }
}

locals {
  cluster_name  = data.terraform_remote_state.cluster.outputs.cluster_name
  dns_zone_name = data.terraform_remote_state.network.outputs.private_dns_zone_name
  name_prefix   = data.terraform_remote_state.network.outputs.name_prefix
}

# AKS Azure CNI Powered by Cilium uses azure-ip-masq-agent (NOT cilium-config)
# for pod masquerade. By default the agent has NonMasqueradeCIDRs=[100.64.0.0/16]
# which preserves pod IPs intra-cluster but masquerades cross-cluster traffic to
# the node IP — hiding pod IPs from DCF inspection at the Aviatrix spoke gateway.
#
# We override the AKS-managed ConfigMap to NonMasqueradeCIDRs=[0.0.0.0/0],
# disabling all cluster-boundary masquerade. Pods now egress with their original
# 100.64.x.x source IPs all the way to the Aviatrix spoke GW, which inspects
# them via DCF and then SNATs to the GW's private IP via customized_snat (see
# network/main.tf aviatrix_gateway_snat.frontend).
#
# `kubernetes_config_map_v1_data` updates the existing AKS-managed ConfigMap's
# data field without taking ownership of the resource itself — the AKS addon
# reconciler won't fight us over fields we don't claim. The agent re-reads its
# config every 60s (--resync-interval default), so changes propagate without
# requiring a daemonset restart.
resource "kubernetes_config_map_v1_data" "azure_ip_masq_agent" {
  metadata {
    name      = "azure-ip-masq-agent-config"
    namespace = "kube-system"
  }
  data = {
    "ip-masq-agent" = yamlencode({
      nonMasqueradeCIDRs = ["0.0.0.0/0"]
      masqLinkLocal      = false
    })
  }
  force = true

  depends_on = [helm_release.k8s_firewall]
}
