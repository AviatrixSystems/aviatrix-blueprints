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

# See nodes/frontend/main.tf for the full rationale on disabling
# cluster-boundary masquerade. Both clusters get the same override so pod IPs
# are preserved end-to-end up to their respective Aviatrix spoke gateway.
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
