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

# In pod-subnet mode AKS does NOT deploy the azure-ip-masq-agent daemonset
# (it's only present in overlay mode). Pod IPs are real VNet addresses from
# the dedicated pod subnet (100.64.0.0/16), so no node-level masquerade is
# applied — pods egress the node with their original source IP and reach
# the Aviatrix spoke GW directly. SNAT happens once at the spoke GW via
# customized_snat (see network/main.tf aviatrix_gateway_snat.frontend),
# which is also where DCF inspection sees the original pod IP for K8s
# SmartGroup matching.
