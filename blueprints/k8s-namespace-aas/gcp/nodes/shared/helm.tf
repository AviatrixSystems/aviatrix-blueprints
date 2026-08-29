#####################
# ExternalDNS
#
# Automatically creates Cloud DNS records for Kubernetes Service, Ingress,
# and Gateway API resources.
# Uses Workload Identity Federation (GCP equivalent of AWS IRSA).
#####################

resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "kube-system"
  version    = var.external_dns_chart_version

  values = [
    yamlencode({
      serviceAccount = {
        create = true
        name   = "external-dns"
        annotations = {
          # Workload Identity Federation binding (GKE equivalent of IRSA)
          "iam.gke.io/gcp-service-account" = data.terraform_remote_state.cluster.outputs.external_dns_service_account_email
        }
      }

      provider = {
        name = "google"
      }

      # Only manage records in this domain
      domainFilters = [data.terraform_remote_state.network.outputs.dns_zone_dns_name]

      # Sync mode: ExternalDNS will create AND delete records
      policy = "sync"

      # Unique identifier for this cluster's records
      txtOwnerId = data.terraform_remote_state.cluster.outputs.cluster_name

      # Google Cloud DNS-specific settings
      extraArgs = [
        "--google-project=${local.gcp_project}",
        "--google-zone-visibility=private"
      ]

      # Sources — include Gateway API routes (GKE-specific)
      sources = ["service", "ingress", "gateway-httproute", "gateway-tlsroute"]
    })
  ]

  depends_on = [
    google_container_node_pool.shared,
  ]
}
