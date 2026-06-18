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
          "service.beta.kubernetes.io/azure-load-balancer-internal"        = "true"
          "service.beta.kubernetes.io/azure-load-balancer-internal-subnet" = data.terraform_remote_state.network.outputs.team_b_aks_system_subnet_name
        }
        type = "LoadBalancer"
      }
      serviceAccount = {
        annotations = {
          "azure.workload.identity/client-id" = data.terraform_remote_state.cluster.outputs.ingress_identity_client_id
        }
      }
      podLabels = {
        "azure.workload.identity/use" = "true"
      }
      nodeSelector = { "nodepool-type" = "user" }
      metrics      = { enabled = true }
    }
  })]

  depends_on = [module.default_node_pool, kubernetes_config_map_v1_data.coredns_custom]
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = var.external_dns_chart_version
  namespace  = "kube-system"

  values = [data.terraform_remote_state.cluster.outputs.external_dns_helm_values]

  set { name = "policy"; value = "sync" }
  set { name = "txtOwnerId"; value = data.terraform_remote_state.cluster.outputs.cluster_name }
  set { name = "nodeSelector.nodepool-type"; value = "user" }

  depends_on = [helm_release.nginx_ingress]
}
