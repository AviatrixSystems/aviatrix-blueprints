# -----------------------------------------------------------------------------
# Pattern C: GKE Production Nodes — Data Sources
# -----------------------------------------------------------------------------

data "google_client_config" "current" {}

data "google_container_cluster" "prod" {
  name     = var.cluster_name
  location = var.gcp_region
  project  = var.gcp_project_id
}
