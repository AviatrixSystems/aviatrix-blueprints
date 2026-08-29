#####################
# GKE Cluster Layer (Layer 2) - Team-B
#####################

provider "google" {
  project = local.gcp_project
  region  = local.gcp_region
}

provider "google-beta" {
  project = local.gcp_project
  region  = local.gcp_region
}

locals {
  cluster_name   = data.terraform_remote_state.network.outputs.team_b_cluster_name
  gcp_project    = data.terraform_remote_state.network.outputs.gcp_project
  gcp_region     = data.terraform_remote_state.network.outputs.gcp_region
  network_name   = data.terraform_remote_state.network.outputs.team_b_network_name
  subnet_name    = data.terraform_remote_state.network.outputs.team_b_gke_nodes_subnet_name
  pods_range     = data.terraform_remote_state.network.outputs.team_b_pod_range_name
  services_range = data.terraform_remote_state.network.outputs.team_b_services_range_name
  master_cidr    = data.terraform_remote_state.network.outputs.team_b_master_cidr
  dns_zone_name  = data.terraform_remote_state.network.outputs.dns_zone_dns_name

  labels = {
    environment = "demo"
    team        = "team-b"
    pattern     = "cluster-aas"
  }
}

#####################
# Service account for the GKE nodes (least-privilege per Google guidance).
#####################

resource "google_service_account" "node" {
  account_id   = "${local.cluster_name}-node-sa"
  display_name = "GKE node SA for ${local.cluster_name}"
  project      = local.gcp_project
}

resource "google_project_iam_member" "node_log_writer" {
  project = local.gcp_project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_metric_writer" {
  project = local.gcp_project
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_monitoring_viewer" {
  project = local.gcp_project
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_resource_metadata" {
  project = local.gcp_project
  role    = "roles/stackdriver.resourceMetadata.writer"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_artifact_reader" {
  project = local.gcp_project
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.node.email}"
}

#####################
# GKE Cluster - Team-B
#####################

resource "google_container_cluster" "this" {
  name     = local.cluster_name
  project  = local.gcp_project
  location = local.gcp_region

  remove_default_node_pool = true
  initial_node_count       = 1

  network         = local.network_name
  subnetwork      = local.subnet_name
  networking_mode = "VPC_NATIVE"

  datapath_provider = "ADVANCED_DATAPATH"

  release_channel {
    channel = var.release_channel
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range
    services_secondary_range_name = local.services_range
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = local.master_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  default_snat_status {
    disabled = true
  }

  workload_identity_config {
    workload_pool = "${local.gcp_project}.svc.id.goog"
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

#####################
# Service account for ExternalDNS (Workload Identity Federation for GKE)
#####################

resource "google_service_account" "external_dns" {
  account_id   = "${local.cluster_name}-edns"
  display_name = "ExternalDNS for ${local.cluster_name}"
  project      = local.gcp_project
}

resource "google_project_iam_member" "external_dns_admin" {
  project = local.gcp_project
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.external_dns.email}"
}

resource "google_service_account_iam_member" "external_dns_wif" {
  service_account_id = google_service_account.external_dns.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.gcp_project}.svc.id.goog[kube-system/external-dns]"

  depends_on = [google_container_cluster.this]
}
