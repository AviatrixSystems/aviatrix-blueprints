# -----------------------------------------------------------------------------
# Pattern C: GKE Non-Production Cluster
# Dedicated non-production cluster in isolated VPC
# VPC-native + Workload Identity Federation
# master_ipv4_cidr_block: 172.16.0.16/28 (different from prod)
# deletion_protection = false
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

module "gke_nonprod" {
  source = "../../../../gcp-gke-multicluster/modules/gke-cluster"

  cluster_name = "${data.terraform_remote_state.network.outputs.name_prefix}-nonprod"
  project_id   = var.gcp_project_id
  region       = var.gcp_region

  # VPC-native networking
  vpc_self_link    = var.vpc_self_link
  subnet_self_link = var.subnet_self_link

  # Control plane CIDR — unique per cluster (different from prod!)
  master_ipv4_cidr_block = var.master_ipv4_cidr_block # 172.16.0.16/28

  # VPC-native pod networking
  ip_range_pods     = "pods"
  ip_range_services = "services"

  # Workload Identity Federation
  workload_identity_enabled = true

  # Kubernetes version
  kubernetes_version = var.kubernetes_version

  # deletion_protection must be false for Terraform management
  deletion_protection = false

  # Default node pool
  default_node_pool = {
    name           = "nonprod-default"
    machine_type   = var.node_machine_type
    min_count      = var.node_min_count
    max_count      = var.node_max_count
    initial_count  = var.initial_node_count
    disk_size_gb   = 100
    disk_type      = "pd-standard"
    node_labels = {
      "environment" = "non-production"
      "cluster"     = "nonprod"
    }
  }

  # Private cluster
  enable_private_nodes    = true
  enable_private_endpoint = false
  master_authorized_networks = []

  labels = {
    environment = "non-production"
    pattern     = "c"
    managed-by  = "terraform"
  }
}

