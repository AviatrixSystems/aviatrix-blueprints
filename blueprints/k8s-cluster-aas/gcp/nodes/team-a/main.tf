#####################
# GKE Node Layer (Layer 3) - Team-A
#
# Provisions:
#   - GKE node pool (inline google_container_node_pool)
#   - Aviatrix Controller onboarding (aviatrix_kubernetes_cluster)
#   - Aviatrix k8s-firewall Helm chart (CRDs)
#   - Gateway API GatewayClass + ExternalDNS (via helm.tf)
#
# NOTE: GKE does not require ENIConfig (unlike EKS). VPC-native networking
# with alias IP ranges handles pod IP assignment automatically.
#####################

provider "google" {
  project = local.gcp_project
  region  = local.gcp_region
}

provider "aviatrix" {
  controller_ip           = var.controller_ip
  username                = var.controller_username
  password                = var.controller_password
  skip_version_validation = true
}

locals {
  gcp_project = data.terraform_remote_state.network.outputs.gcp_project
  gcp_region  = data.terraform_remote_state.network.outputs.gcp_region

  cluster_name             = data.terraform_remote_state.cluster.outputs.cluster_name
  cluster_location         = data.terraform_remote_state.cluster.outputs.cluster_location
  node_service_account     = "${local.cluster_name}-node-sa@${local.gcp_project}.iam.gserviceaccount.com"
  external_dns_helm_values = data.terraform_remote_state.cluster.outputs.external_dns_helm_values
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

  depends_on = [google_container_node_pool.default]
}

#####################
# Aviatrix k8s-firewall (CRDs - optional in Pattern A)
#####################

resource "helm_release" "k8s_firewall" {
  name       = "k8s-firewall"
  repository = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart      = "k8s-firewall"
  namespace  = "default"
  wait       = false

  depends_on = [google_container_node_pool.default]
}

#####################
# Team-A GKE Node Pool (inline — replaces broken gke-node-pool module)
#####################

resource "google_container_node_pool" "default" {
  name     = "default"
  project  = local.gcp_project
  location = local.cluster_location
  cluster  = local.cluster_name

  node_count = var.node_pool_config.initial_node_count

  autoscaling {
    min_node_count = var.node_pool_config.min_node_count
    max_node_count = var.node_pool_config.max_node_count
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
    disk_size_gb = 100
    disk_type    = "pd-balanced"
    spot         = var.node_pool_config.spot

    service_account = local.node_service_account
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Workload Identity for pod-level IAM (used by ExternalDNS in helm.tf).
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      environment = "demo"
      team        = "team-a"
      pattern     = "cluster-aas"
    }
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}
