#####################
# Aviatrix Controller Onboarding
#
# Registers the GKE cluster with the Aviatrix Controller so DCF SmartGroups
# can target Kubernetes-typed selectors (cluster, namespace, service, pod)
# instead of just VPC selectors.
#
# Auth flow:
#   1. Controller calls GKE container.googleapis.com via the Aviatrix GCP
#      access account's service account to fetch a kubeconfig.
#   2. Controller connects to the cluster's public master endpoint with that
#      kubeconfig (the master endpoint must allow the controller's egress IP
#      via master_authorized_networks).
#
# Requirements (NOT enforced by Terraform — pre-checks for the operator):
#   - Aviatrix GCP access account onboarded (see network/, var.aviatrix_gcp_account_name).
#   - That account's service account has roles/container.viewer (read kubeconfig)
#     and roles/container.admin or equivalent (lookup cluster details). The
#     "Kubernetes Engine Admin" predefined role works.
#   - Controller's public egress IP is in the cluster's master_authorized_networks
#     (see var.aviatrix_controller_public_ip).
#####################

resource "aviatrix_kubernetes_cluster" "this" {
  count = var.enable_aviatrix_onboarding ? 1 : 0

  cluster_id          = google_container_cluster.this.self_link
  use_csp_credentials = true

  depends_on = [
    google_container_cluster.this,
    google_container_node_pool.primary,
  ]
}
