#####################
# Gateway API Setup
#
# GKE has built-in Gateway API support (enabled in the cluster module via gateway_api_config).
# Unlike EKS which requires the AWS Load Balancer Controller Helm chart, GKE's GCE ingress
# controller and Gateway API implementation are managed by GKE itself.
#
# Deploy a default GatewayClass for internal load balancing via Gateway API.
#####################

resource "kubernetes_manifest" "internal_gateway_class" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "GatewayClass"
    metadata = {
      name = "gke-l7-rilb"
    }
    spec = {
      controllerName = "networking.gke.io/gateway"
      description    = "GKE internal regional L7 load balancer via Gateway API"
    }
  }

  depends_on = [module.shared_node_pool]
}

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
    module.shared_node_pool,
  ]
}
