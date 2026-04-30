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

# See nodes/frontend/main.tf — pod-subnet mode means AKS doesn't deploy the
# azure-ip-masq-agent daemonset; no cluster-boundary masquerade override is
# needed. Pod IPs are preserved end-to-end up to the Aviatrix spoke gateway.
