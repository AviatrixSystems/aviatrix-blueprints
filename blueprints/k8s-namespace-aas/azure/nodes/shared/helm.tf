#####################
# NGINX Ingress Controller
#
# Creates an Azure Internal Load Balancer for ingress traffic.
# Uses Workload Identity for Azure API access.
#####################

resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.nginx_ingress_chart_version
  namespace  = "kube-system"

  values = [yamlencode({
    controller = {
      replicaCount = 2

      service = {
        annotations = {
          # Create an internal Azure Load Balancer (not public-facing)
          "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
          # Place LB in the AKS subnet
          "service.beta.kubernetes.io/azure-load-balancer-internal-subnet" = data.terraform_remote_state.network.outputs.shared_aks_system_subnet_name
        }
        type = "LoadBalancer"
      }

      # Use Workload Identity for Azure API access
      serviceAccount = {
        annotations = {
          "azure.workload.identity/client-id" = data.terraform_remote_state.cluster.outputs.ingress_identity_client_id
        }
      }

      podLabels = {
        "azure.workload.identity/use" = "true"
      }

      nodeSelector = {
        "nodepool-type" = "shared"
      }

      metrics = {
        enabled = true
      }
    }
  })]

  depends_on = [module.shared_node_pool, kubernetes_config_map_v1_data.coredns_custom]
}

#####################
# ExternalDNS
#
# Automatically creates Azure Private DNS records for Kubernetes Services/Ingresses.
# Uses Workload Identity (federated credential) to authenticate with Azure DNS API.
#####################

resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = var.external_dns_chart_version
  namespace  = "kube-system"

  # Use pre-computed Helm values from cluster module
  values = [data.terraform_remote_state.cluster.outputs.external_dns_helm_values]

  set {
    name  = "policy"
    value = "sync"
  }

  set {
    name  = "txtOwnerId"
    value = data.terraform_remote_state.cluster.outputs.cluster_name
  }

  set {
    name  = "nodeSelector.nodepool-type"
    value = "shared"
  }

  depends_on = [helm_release.nginx_ingress]
}
