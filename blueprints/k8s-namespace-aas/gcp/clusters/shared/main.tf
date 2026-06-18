#####################
# Pattern B: Namespace-as-a-Service — GCP Shared GKE Cluster (Layer 2)
#
# Provisions a single shared GKE cluster. All teams (team-a, team-b, team-c)
# get isolated namespaces within this cluster.
#
# Isolation is enforced by DCF SmartGroups (k8s_namespace type), NOT by RBAC alone.
# RBAC is NOT a hard security boundary — DCF is the primary network isolation.
#
# Authentication:
#   - Aviatrix: AVIATRIX_CONTROLLER_IP, AVIATRIX_USERNAME, AVIATRIX_PASSWORD env vars
#   - GCP: gcloud auth application-default login or GOOGLE_CREDENTIALS env var
#####################

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = local.gcp_project
  region  = local.gcp_region
}

provider "google-beta" {
  project = local.gcp_project
  region  = local.gcp_region
}

locals {
  cluster_name = data.terraform_remote_state.network.outputs.shared_cluster_name
  gcp_project  = data.terraform_remote_state.network.outputs.gcp_project
  gcp_region   = data.terraform_remote_state.network.outputs.gcp_region
}

# Kubernetes provider — connects to GKE cluster using gcloud exec auth
provider "kubernetes" {
  host                   = "https://${module.shared_gke.cluster_endpoint}"
  cluster_ca_certificate = base64decode(module.shared_gke.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

#####################
# Shared GKE Cluster (Control Plane Only)
#
# Uses the gke-cluster module for the control plane.
# Node pools are managed separately in Layer 3 (nodes/).
# GKE VPC-native with alias IP ranges handles pod networking.
# Workload Identity Federation is the GCP equivalent of AWS IRSA.
# deletion_protection = false for demo environments.
#####################

module "shared_gke" {
  source = "../../../../gcp-gke-multicluster/modules/gke-cluster"

  cluster_name = local.cluster_name
  project      = local.gcp_project
  region       = local.gcp_region

  # Network configuration from Layer 1
  network              = data.terraform_remote_state.network.outputs.shared_network_name
  subnetwork           = data.terraform_remote_state.network.outputs.shared_gke_nodes_subnet_name
  pod_range_name       = data.terraform_remote_state.network.outputs.shared_pod_range_name
  services_range_name  = data.terraform_remote_state.network.outputs.shared_services_range_name
  master_ipv4_cidr_block = data.terraform_remote_state.network.outputs.master_ipv4_cidr_block

  # Cloud DNS configuration for ExternalDNS
  dns_zone_name     = data.terraform_remote_state.network.outputs.dns_zone_name
  dns_zone_dns_name = data.terraform_remote_state.network.outputs.dns_zone_dns_name

  # Aviatrix Controller onboarding
  enable_aviatrix_onboarding = true

  # Release channel
  release_channel = var.release_channel

  # Master authorized networks
  master_authorized_networks = var.master_authorized_networks

  labels = {
    environment = "prod"
    pattern     = "namespace-aas"
  }
}

