# -----------------------------------------------------------------------------
# Pattern C: GKE Non-Production Nodes - inline node pool + Helm Deployments
# Aviatrix k8s-firewall for DCF Layer 2 enforcement
# -----------------------------------------------------------------------------

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "aviatrix" {
  controller_ip           = var.controller_ip
  username                = var.controller_username
  password                = var.controller_password
  skip_version_validation = true
}

provider "helm" {
  kubernetes {
    host                   = "https://${var.cluster_endpoint}"
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
    token                  = data.google_client_config.current.access_token
  }
}

provider "kubernetes" {
  host                   = "https://${var.cluster_endpoint}"
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
  token                  = data.google_client_config.current.access_token
}

locals {
  node_service_account = "${var.cluster_name}-node-sa@${var.gcp_project_id}.iam.gserviceaccount.com"
}

# ---------------------------------------------------------------------------
# Non-Production GKE Node Pool (inline — replaces broken gke-node-pool module)
# ---------------------------------------------------------------------------

resource "google_container_node_pool" "nonprod_default" {
  name     = "nonprod-default"
  project  = var.gcp_project_id
  location = var.gcp_region
  cluster  = var.cluster_name

  node_count = var.initial_node_count

  autoscaling {
    min_node_count = var.node_min_count
    max_node_count = var.node_max_count
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
    machine_type = var.node_machine_type
    disk_size_gb = 100
    disk_type    = "pd-standard"

    service_account = local.node_service_account
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      "environment" = "non-production"
      "cluster"     = "nonprod"
    }
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

# ---------------------------------------------------------------------------
# Aviatrix Kubernetes Cluster Onboarding
# ---------------------------------------------------------------------------

resource "aviatrix_kubernetes_cluster" "this" {
  cluster_id          = var.cluster_id
  use_csp_credentials = true

  depends_on = [google_container_node_pool.nonprod_default]
}

# ---------------------------------------------------------------------------
# Aviatrix Kubernetes Firewall (DCF Layer 2 enforcement)
# ---------------------------------------------------------------------------

resource "helm_release" "aviatrix_k8s_firewall" {
  name             = "aviatrix-k8s-firewall"
  namespace        = "aviatrix-system"
  create_namespace = true
  repository       = "https://aviatrix-download.s3.us-west-2.amazonaws.com/helm-charts"
  chart            = "aviatrix-k8s-firewall"
  version          = "1.0.0"

  set {
    name  = "controllerIP"
    value = var.aviatrix_controller_ip
  }

  set {
    name  = "controllerUsername"
    value = var.aviatrix_username
  }

  set_sensitive {
    name  = "controllerPassword"
    value = var.aviatrix_password
  }

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "cloud"
    value = "GCP"
  }

  set {
    name  = "enableCRD"
    value = "true"
  }

  depends_on = [google_container_node_pool.nonprod_default]
}
