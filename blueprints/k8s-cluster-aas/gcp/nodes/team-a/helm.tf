#####################
# Gateway API Setup
#
# GKE has built-in Gateway API support (enabled in the cluster module).
# Deploy a default GatewayClass for internal load balancing.
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

  depends_on = [module.default_node_pool]
}

#####################
# ExternalDNS
#
# Automatically creates Cloud DNS records for Kubernetes resources.
# Uses Workload Identity Federation for authentication.
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
          "iam.gke.io/gcp-service-account" = data.terraform_remote_state.cluster.outputs.external_dns_service_account_email
        }
      }

      provider = {
        name = "google"
      }

      domainFilters = [data.terraform_remote_state.network.outputs.dns_zone_dns_name]
      policy        = "sync"
      txtOwnerId    = data.terraform_remote_state.cluster.outputs.cluster_name

      extraArgs = [
        "--google-project=${local.gcp_project}",
        "--google-zone-visibility=private"
      ]

      sources = ["service", "ingress", "gateway-httproute", "gateway-tlsroute"]
    })
  ]

  depends_on = [module.default_node_pool]
}
