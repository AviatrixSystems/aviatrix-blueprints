#####################
# GKE Cluster Layer (Layer 2) - Team-C
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
  cluster_name = data.terraform_remote_state.network.outputs.team_c_cluster_name
  gcp_project  = data.terraform_remote_state.network.outputs.gcp_project
  gcp_region   = data.terraform_remote_state.network.outputs.gcp_region
}

provider "kubernetes" {
  host                   = "https://${module.team_c_gke.cluster_endpoint}"
  cluster_ca_certificate = base64decode(module.team_c_gke.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

module "team_c_gke" {
  source = "../../../../gcp-gke-multicluster/modules/gke-cluster"

  cluster_name = local.cluster_name
  project      = local.gcp_project
  region       = local.gcp_region

  network                = data.terraform_remote_state.network.outputs.team_c_network_name
  subnetwork             = data.terraform_remote_state.network.outputs.team_c_gke_nodes_subnet_name
  pod_range_name         = data.terraform_remote_state.network.outputs.team_c_pod_range_name
  services_range_name    = data.terraform_remote_state.network.outputs.team_c_services_range_name
  master_ipv4_cidr_block = data.terraform_remote_state.network.outputs.team_c_master_cidr

  dns_zone_name     = data.terraform_remote_state.network.outputs.dns_zone_name
  dns_zone_dns_name = data.terraform_remote_state.network.outputs.dns_zone_dns_name

  enable_aviatrix_onboarding = true
  deletion_protection        = false

  release_channel            = var.release_channel
  master_authorized_networks = var.master_authorized_networks

  labels = {
    environment = "demo"
    team        = "team-c"
    pattern     = "cluster-aas"
  }
}

