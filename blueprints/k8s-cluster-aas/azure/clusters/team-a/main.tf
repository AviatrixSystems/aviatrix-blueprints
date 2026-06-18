#####################
# AKS Cluster Layer (Layer 2) - Team-A
#
# Provisions the AKS control plane using outputs from the network layer.
# Node pools are managed separately in Layer 3 (nodes/).
# Each team is cluster-admin in their own cluster (Pattern A isolation).
#####################

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = data.terraform_remote_state.network.outputs.azure_subscription_id
}

provider "azuread" {}

provider "kubernetes" {
  host                   = module.team_a_aks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.team_a_aks.cluster_certificate_authority_data)

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

#####################
# Team-A AKS Cluster
# Module source: ../../../azure-aks-multicluster/modules/aks-cluster
#####################

module "team_a_aks" {
  source = "../../../../azure-aks-multicluster/modules/aks-cluster"

  cluster_name        = data.terraform_remote_state.network.outputs.team_a_cluster_name
  resource_group_name = data.terraform_remote_state.network.outputs.team_a_resource_group_name
  location            = data.terraform_remote_state.network.outputs.azure_region
  kubernetes_version  = var.kubernetes_version

  aks_subnet_id = data.terraform_remote_state.network.outputs.team_a_aks_system_subnet_id
  pod_cidr      = data.terraform_remote_state.network.outputs.pod_cidr

  private_dns_zone_id                  = data.terraform_remote_state.network.outputs.private_dns_zone_id
  private_dns_zone_name                = data.terraform_remote_state.network.outputs.private_dns_zone_name
  private_dns_zone_resource_group_name = data.terraform_remote_state.network.outputs.private_dns_zone_resource_group

  enable_aviatrix_onboarding = true

  tags = {
    Environment = "demo"
    Team        = "team-a"
    Terraform   = "true"
    Pattern     = "cluster-aas"
  }
}

#####################
# Outputs
#####################

output "cluster_name" {
  value = module.team_a_aks.cluster_name
}

output "cluster_endpoint" {
  value = module.team_a_aks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value     = module.team_a_aks.cluster_certificate_authority_data
  sensitive = true
}

output "oidc_issuer_url" {
  value = module.team_a_aks.oidc_issuer_url
}

output "external_dns_identity_client_id" {
  value = module.team_a_aks.external_dns_identity_client_id
}

output "ingress_identity_client_id" {
  value = module.team_a_aks.ingress_identity_client_id
}

output "external_dns_helm_values" {
  value = module.team_a_aks.external_dns_helm_values
}

output "kube_config_raw" {
  value     = module.team_a_aks.kube_config_raw
  sensitive = true
}

output "cluster_id" {
  description = "AKS cluster ID for Aviatrix onboarding"
  value       = module.team_a_aks.cluster_id
}
