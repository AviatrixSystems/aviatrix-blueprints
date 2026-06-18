#####################
# Pattern B: Namespace-as-a-Service — Azure Shared AKS Cluster (Layer 2)
#
# Provisions a single shared AKS cluster. All teams (team-a, team-b, team-c)
# get isolated namespaces within this cluster.
#
# Isolation is enforced by DCF SmartGroups (k8s_namespace type), NOT by RBAC alone.
# RBAC is NOT a hard security boundary — DCF is the primary network isolation.
#
# Authentication:
#   - Aviatrix: AVIATRIX_CONTROLLER_IP, AVIATRIX_USERNAME, AVIATRIX_PASSWORD env vars
#   - Azure: az login or service principal env vars (ARM_*)
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
  host                   = module.shared_aks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.shared_aks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "az"
    args = [
      "aks", "get-credentials",
      "--resource-group", data.terraform_remote_state.network.outputs.shared_resource_group_name,
      "--name", data.terraform_remote_state.network.outputs.shared_cluster_name,
      "--format", "exec-credential"
    ]
  }
}

#####################
# Shared AKS Cluster
#
# Uses the aks-cluster module for the control plane.
# Node pools are managed separately in Layer 3 (nodes/).
# Azure CNI Overlay handles pod networking — pods get IPs from
# the overlay CIDR (100.64.0.0/16).
# Workload Identity is the Azure equivalent of AWS IRSA.
#####################

module "shared_aks" {
  source = "../../../../azure-aks-multicluster/modules/aks-cluster"

  cluster_name        = data.terraform_remote_state.network.outputs.shared_cluster_name
  resource_group_name = data.terraform_remote_state.network.outputs.shared_resource_group_name
  location            = data.terraform_remote_state.network.outputs.azure_region
  kubernetes_version  = var.kubernetes_version

  # Network configuration from Layer 1
  aks_subnet_id = data.terraform_remote_state.network.outputs.shared_aks_system_subnet_id
  pod_cidr      = data.terraform_remote_state.network.outputs.pod_cidr

  # Private DNS for ExternalDNS
  private_dns_zone_id                  = data.terraform_remote_state.network.outputs.private_dns_zone_id
  private_dns_zone_name                = data.terraform_remote_state.network.outputs.private_dns_zone_name
  private_dns_zone_resource_group_name = data.terraform_remote_state.network.outputs.private_dns_zone_resource_group

  # Aviatrix onboarding for SmartGroup visibility
  enable_aviatrix_onboarding = true

  tags = {
    Environment = "prod"
    Pattern     = "namespace-aas"
    Terraform   = "true"
  }
}

