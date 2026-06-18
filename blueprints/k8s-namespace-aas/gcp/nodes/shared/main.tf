#####################
# Pattern B: Namespace-as-a-Service — GCP Node Layer (Layer 3)
#
# Provisions:
#   - GKE node pool via gke-node-pool module
#   - Aviatrix k8s-firewall Helm chart (CRDs for in-cluster DCF policies)
#   - Gateway API + ExternalDNS via helm.tf
#
# This layer runs AFTER:
#   - Layer 1 (network/) — VPC, Aviatrix transit/spoke, Cloud DNS
#   - Layer 2 (clusters/) — GKE control plane, Workload Identity Federation
#####################

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
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

provider "google" {
  project = local.gcp_project
  region  = local.gcp_region
}

provider "aviatrix" {
  skip_version_validation = true
}

locals {
  gcp_project = data.terraform_remote_state.network.outputs.gcp_project
  gcp_region  = data.terraform_remote_state.network.outputs.gcp_region
}

# Kubernetes provider for Kubernetes resources
provider "kubernetes" {
  host                   = "https://${data.terraform_remote_state.cluster.outputs.cluster_endpoint}"
  cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

# Helm provider for Kubernetes add-ons
provider "helm" {
  kubernetes {
    host                   = "https://${data.terraform_remote_state.cluster.outputs.cluster_endpoint}"
    cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
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
# Shared GKE Node Pool
#
# Single shared node pool for all team namespaces.
# NOTE: GKE does not require ENIConfig (unlike EKS). VPC-native networking
# with alias IP ranges handles pod IP assignment automatically via secondary ranges.
#####################

module "shared_node_pool" {
  source = "../../../../gcp-gke-multicluster/modules/gke-node-pool"

  # Cluster identity — from cluster state (exists at plan time)
  cluster_name = data.terraform_remote_state.cluster.outputs.cluster_name
  project      = local.gcp_project
  location     = data.terraform_remote_state.cluster.outputs.cluster_location

  # Scaling configuration
  node_pool_name     = "shared"
  min_node_count     = var.node_pool_config.min_node_count
  max_node_count     = var.node_pool_config.max_node_count
  initial_node_count = var.node_pool_config.initial_node_count

  # Instance configuration
  machine_type = var.node_pool_config.machine_type
  spot         = var.node_pool_config.spot

  labels = {
    environment     = "prod"
    pattern         = "namespace-aas"
    "nodepool-type" = "shared"
  }
}
