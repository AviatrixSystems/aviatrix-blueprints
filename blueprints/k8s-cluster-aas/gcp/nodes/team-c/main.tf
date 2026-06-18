#####################
# GKE Node Layer (Layer 3) - Team-C
#####################

terraform {
  required_version = ">= 1.5"

  required_providers {
    google     = { source = "hashicorp/google", version = "~> 6.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.0" }
    helm       = { source = "hashicorp/helm", version = "~> 2.0" }
    aviatrix   = { source = "AviatrixSystems/aviatrix", version = "~> 8.2.0" }
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

provider "kubernetes" {
  host                   = "https://${data.terraform_remote_state.cluster.outputs.cluster_endpoint}"
  cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

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

resource "helm_release" "k8s_firewall" {
  name       = "k8s-firewall"
  repository = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart      = "k8s-firewall"
  namespace  = "default"
  wait       = false
}

module "default_node_pool" {
  source = "../../../../gcp-gke-multicluster/modules/gke-node-pool"

  cluster_name = data.terraform_remote_state.cluster.outputs.cluster_name
  project      = local.gcp_project
  location     = data.terraform_remote_state.cluster.outputs.cluster_location

  node_pool_name     = "default"
  min_node_count     = var.node_pool_config.min_node_count
  max_node_count     = var.node_pool_config.max_node_count
  initial_node_count = var.node_pool_config.initial_node_count
  machine_type       = var.node_pool_config.machine_type
  spot               = var.node_pool_config.spot

  labels = {
    environment = "demo"
    team        = "team-c"
    pattern     = "cluster-aas"
  }
}
