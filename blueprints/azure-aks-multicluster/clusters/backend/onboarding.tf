#####################
# Aviatrix Controller Onboarding
#
# Registers the AKS cluster with the Aviatrix Controller so DCF SmartGroups
# can target Kubernetes-typed selectors (cluster, namespace, service, pod)
# instead of just VNet selectors.
#
# Auth flow (per docs.aviatrix.com/docs/enterprise/8.2/guides/security/dcf/kubernetes-onboard):
#   1. Controller calls ARM listClusterUserCredential/action via the Aviatrix
#      Azure access account's service principal to fetch a local-account
#      kubeconfig from the AKS cluster.
#   2. Controller connects to the AKS API server FQDN with that kubeconfig.
#
# Requirements (NOT enforced by Terraform — pre-checks for the operator):
#   - Aviatrix Azure access account onboarded (see network/main.tf, var.aviatrix_azure_account_name).
#   - That account's SP has Microsoft.ContainerService/managedClusters/listClusterUserCredential/action
#     at subscription scope. Contributor includes it.
#   - AKS cluster uses Kubernetes RBAC with local accounts. Entra-ID-only
#     auth is NOT supported — the kubeconfig returned would contain `exec`
#     entries the controller cannot process.
#   - Controller's public egress IP is in the AKS API server's authorized_ip_ranges
#     (see var.aviatrix_controller_public_ip).
#####################

resource "aviatrix_kubernetes_cluster" "this" {
  count = var.enable_aviatrix_onboarding ? 1 : 0

  # Docs require lowercased cluster_id. azurerm_kubernetes_cluster.id is
  # mixed-case ("/subscriptions/.../Microsoft.ContainerService/managedClusters/...").
  cluster_id          = lower(azurerm_kubernetes_cluster.aks.id)
  use_csp_credentials = true

  depends_on = [azurerm_kubernetes_cluster.aks]
}
