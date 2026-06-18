# -----------------------------------------------------------------------------
# Pattern C: GKE Non-Production Cluster — Data Sources
# -----------------------------------------------------------------------------

data "terraform_remote_state" "network" {
  backend = "local"
  config = {
    path = "../../network/terraform.tfstate"
  }
}

data "google_project" "current" {
  project_id = var.gcp_project_id
}

data "google_client_config" "current" {}

data "google_container_engine_versions" "available" {
  project  = var.gcp_project_id
  location = var.gcp_region
}
