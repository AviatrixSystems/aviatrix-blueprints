provider "google" {
  project = local.project_id
  region  = local.region
}

provider "aviatrix" {
  controller_ip           = var.aviatrix_controller_ip
  username                = var.aviatrix_username
  password                = var.aviatrix_password
  skip_version_validation = true
}

locals {
  cluster_name   = data.terraform_remote_state.network.outputs.backend_cluster_name
  project_id     = data.terraform_remote_state.network.outputs.gcp_project_id
  region         = data.terraform_remote_state.network.outputs.gcp_region
  zone           = data.terraform_remote_state.network.outputs.gcp_zone
  vpc_self_link  = data.terraform_remote_state.network.outputs.backend_vpc_self_link
  nodes_subnet   = data.terraform_remote_state.network.outputs.backend_nodes_subnet_name
  pods_range     = data.terraform_remote_state.network.outputs.backend_pods_range_name
  services_range = data.terraform_remote_state.network.outputs.backend_services_range_name
  master_cidr    = data.terraform_remote_state.network.outputs.backend_master_cidr
  spoke_gw_ip    = data.terraform_remote_state.network.outputs.backend_spoke_gateway_public_ip

  # GKE master authorized networks = user IPs ∪ {spoke GW egress IP} ∪ {controller IP if onboarding enabled}.
  # Spoke GW egress is required because GKE node→master health checks egress
  # via the spoke (the master endpoint is public). Controller IP is required
  # because the onboarding flow has the controller call the GKE API server
  # directly after fetching credentials via the GCP access account.
  authorized_networks = concat(
    [for cidr in var.master_authorized_cidr_blocks : { cidr_block = cidr, display_name = "user" }],
    [{ cidr_block = "${local.spoke_gw_ip}/32", display_name = "aviatrix-spoke-egress" }],
    var.enable_aviatrix_onboarding && var.aviatrix_controller_public_ip != null
    ? [{ cidr_block = "${var.aviatrix_controller_public_ip}/32", display_name = "aviatrix-controller" }]
    : [],
  )
}

#####################
# Service account for the GKE nodes
#####################

resource "google_service_account" "node" {
  account_id   = "${local.cluster_name}-node-sa"
  display_name = "GKE node SA for ${local.cluster_name}"
  project      = local.project_id
}

# Minimum permissions for GKE nodes per
# https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster#use_least_privilege_sa
resource "google_project_iam_member" "node_log_writer" {
  project = local.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_metric_writer" {
  project = local.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_monitoring_viewer" {
  project = local.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_resource_metadata" {
  project = local.project_id
  role    = "roles/stackdriver.resourceMetadata.writer"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_artifact_reader" {
  project = local.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.node.email}"
}

#####################
# GKE cluster
#####################

resource "google_container_cluster" "this" {
  name     = local.cluster_name
  project  = local.project_id
  location = local.zone

  # Manage the system node pool separately (best practice — lets us recreate
  # node pools without destroying the cluster control plane).
  remove_default_node_pool = true
  initial_node_count       = 1

  network         = local.vpc_self_link
  subnetwork      = local.nodes_subnet
  networking_mode = "VPC_NATIVE"

  # Dataplane V2 = Cilium-based eBPF. Replaces kube-proxy; provides network
  # policy + observability. NetworkPolicy enforcement is enabled by default
  # under DPV2, so the legacy network_policy block is omitted.
  datapath_provider = "ADVANCED_DATAPATH"

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range
    services_secondary_range_name = local.services_range
  }

  # Private nodes (no public IPs) but public master endpoint with allowlist.
  # Node egress flows through the Aviatrix spoke GW via the VPC's default
  # route (programmed by Aviatrix 9.0).
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = local.master_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = local.authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Pod source IPs reach the spoke GW unmasqueraded — Aviatrix SNATs them.
  # Equivalent to Cilium enableIPv4Masquerade=false in the AKS variant.
  default_snat_status {
    disabled = true
  }

  workload_identity_config {
    workload_pool = "${local.project_id}.svc.id.goog"
  }

  # Enable Gateway API CRDs — backs `gke-l7-global-external-managed` Gateway
  # provisioning by the GKE controller.
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # Required deletion-protection knob — explicit so destroy works in lab use.
  deletion_protection = false

  # Release channel advances master_version out of band — let it drift.
  lifecycle {
    ignore_changes = [min_master_version]
  }
}

#####################
# Node pool
#####################

resource "google_container_node_pool" "primary" {
  name       = "primary"
  project    = local.project_id
  location   = local.zone
  cluster    = google_container_cluster.this.name
  node_count = var.node_pool_config.initial_count

  autoscaling {
    min_node_count = var.node_pool_config.min_count
    max_node_count = var.node_pool_config.max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.node_pool_config.machine_type
    disk_size_gb = var.node_pool_config.disk_size_gb
    disk_type    = "pd-balanced"

    service_account = google_service_account.node.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Workload Identity for pod-level IAM (used by ExternalDNS in nodes/).
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      environment = "demo"
      blueprint   = "gcp-gke-multicluster"
      cluster     = "backend"
    }
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

#####################
# Service account for ExternalDNS (Workload Identity Federation for GKE)
#
# Bound to KSA `kube-system/external-dns` via roles/iam.workloadIdentityUser.
# The KSA is created by the ExternalDNS Helm chart in nodes/frontend.
#####################

resource "google_service_account" "external_dns" {
  account_id   = "${local.cluster_name}-edns"
  display_name = "ExternalDNS for ${local.cluster_name}"
  project      = local.project_id
}

# Manage records in the private Cloud DNS zone.
resource "google_project_iam_member" "external_dns_admin" {
  project = local.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.external_dns.email}"
}

# Bind the KSA to the GSA — Workload Identity Federation for GKE.
# The pool `<project>.svc.id.goog` only exists once a cluster with
# workload_identity_config has been created — explicit dep avoids the race.
resource "google_service_account_iam_member" "external_dns_wif" {
  service_account_id = google_service_account.external_dns.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.project_id}.svc.id.goog[kube-system/external-dns]"

  depends_on = [google_container_cluster.this]
}
