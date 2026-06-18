provider "google" {
  project = data.terraform_remote_state.network.outputs.gcp_project_id
  region  = data.terraform_remote_state.network.outputs.gcp_region
}

# Use the active gcloud credentials' OAuth token to authenticate against the
# GKE API server. This requires `gcloud auth application-default login` to
# have been run (or the operator's environment provides an ADC token).
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${data.terraform_remote_state.cluster.outputs.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${data.terraform_remote_state.cluster.outputs.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_ca_certificate)
  }
}

locals {
  cluster_name     = data.terraform_remote_state.cluster.outputs.cluster_name
  project_id       = data.terraform_remote_state.network.outputs.gcp_project_id
  dns_zone_name    = trimsuffix(data.terraform_remote_state.network.outputs.private_dns_zone_name, ".")
  external_dns_gsa = data.terraform_remote_state.cluster.outputs.external_dns_service_account_email
  name_prefix      = data.terraform_remote_state.network.outputs.name_prefix
}
