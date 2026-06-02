# -----------------------------------------------------------------------------
# Pattern C: GKE Production Cluster (inline — replaces broken gke-cluster module)
# Dedicated production cluster in isolated VPC
# VPC-native + Workload Identity Federation
# master_ipv4_cidr_block: 172.16.0.0/28 (unique per cluster)
# deletion_protection = false
#
# The previous `gke-cluster` module reference does not exist on disk; this
# workspace inlines google_container_cluster directly. Node pool is moved
# to nodes/prod (canonical pattern from gcp-gke-multicluster/clusters/frontend).
# -----------------------------------------------------------------------------

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

locals {
  # Use the name_prefix from remote state when available, fall back to environment_prefix.
  # This ensures destroy works even when the network layer has already been removed.
  name_prefix  = try(data.terraform_remote_state.network.outputs.name_prefix, var.environment_prefix)
  cluster_name = "${local.name_prefix}-prod"

  labels = {
    environment = "production"
    pattern     = "c"
    managed-by  = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Service account for the GKE nodes (least-privilege)
# -----------------------------------------------------------------------------

resource "google_service_account" "node" {
  account_id   = "${local.cluster_name}-node-sa"
  display_name = "GKE node SA for ${local.cluster_name}"
  project      = var.gcp_project_id
}

resource "google_project_iam_member" "node_log_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_metric_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_monitoring_viewer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_resource_metadata" {
  project = var.gcp_project_id
  role    = "roles/stackdriver.resourceMetadata.writer"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_artifact_reader" {
  project = var.gcp_project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.node.email}"
}

# -----------------------------------------------------------------------------
# Production GKE Cluster (control plane only — node pool managed in nodes/prod)
# -----------------------------------------------------------------------------

resource "google_container_cluster" "prod" {
  name     = local.cluster_name
  project  = var.gcp_project_id
  location = var.gcp_region

  remove_default_node_pool = true
  initial_node_count       = 1

  network         = var.vpc_self_link
  subnetwork      = var.subnet_self_link
  networking_mode = "VPC_NATIVE"

  datapath_provider = "ADVANCED_DATAPATH"

  min_master_version = var.kubernetes_version

  ip_allocation_policy {
    cluster_ipv4_cidr_block  = var.pod_cidr
    services_ipv4_cidr_block = "/22"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # No master_authorized_networks_config: previous module call passed
  # `master_authorized_networks = []`, which means no allowlist is set.
  # Omitting the block leaves the master endpoint open to all (lab).

  default_snat_status {
    disabled = true
  }

  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  deletion_protection = false

  resource_labels = local.labels

  lifecycle {
    ignore_changes = [min_master_version]
  }
}
