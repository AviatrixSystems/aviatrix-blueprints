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
# for pod masquerade. In pod-subnet mode the agent's default behavior would
# masquerade pod traffic destined OFF the pod CIDR (e.g., to other VNets via
# transit, or the internet) to the node IP — hiding pod IPs from DCF
# inspection at the Aviatrix spoke gateway.
#
# We override the AKS-managed ConfigMap to NonMasqueradeCIDRs=[0.0.0.0/0],
# disabling cluster-boundary masquerade entirely. Pods now egress with their
# original 100.64.x.x source IPs all the way to the spoke GW, which inspects
# them via DCF and then SNATs to its own private IP via customized_snat (see
# network/main.tf aviatrix_gateway_snat.frontend).
#
# The `azure-ip-masq-agent-config` ConfigMap is NOT pre-created by AKS — only
# `-reconciled` exists by default. The daemonset volume mount marks it
# `optional: true`, so we create the user-overridable variant here. The agent
# re-reads its config every 60s (--resync-interval default), so changes
# propagate without requiring a daemonset restart.
resource "kubernetes_config_map" "azure_ip_masq_agent" {
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

  depends_on = [helm_release.k8s_firewall]
}
