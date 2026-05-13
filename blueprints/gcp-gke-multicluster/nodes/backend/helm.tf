#####################
# ExternalDNS — Cloud DNS provider via Workload Identity Federation
#
# The ExternalDNS Helm chart creates KSA `kube-system/external-dns`. The
# `iam.gke.io/gcp-service-account` annotation links it to the Google service
# account created in clusters/frontend (which already has roles/dns.admin
# bound). The KSA → GSA Workload Identity binding is also in clusters/frontend.
#
# `gateway-httproute` is included in `sources` so ExternalDNS publishes
# A records for HTTPRoute hostnames once the Gateway API resources land in
# k8s-apps/.
#####################

resource "helm_release" "external_dns" {
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  version          = var.external_dns_chart_version
  namespace        = "kube-system"
  create_namespace = false

  values = [
    yamlencode({
      provider = {
        name = "google"
      }

      google = {
        project = local.project_id
      }

      serviceAccount = {
        create = true
        name   = "external-dns"
        annotations = {
          "iam.gke.io/gcp-service-account" = local.external_dns_gsa
        }
      }

      sources = [
        "service",
        "ingress",
        "gateway-httproute",
      ]

      domainFilters = [local.dns_zone_name]

      policy = "sync"

      txtOwnerId = local.cluster_name
      txtPrefix  = "${local.cluster_name}-"

      logLevel = "info"
    })
  ]
}

#####################
# Aviatrix K8s Firewall (DCF CRD Controller)
#
# Installs FirewallPolicy and WebGroupPolicy CRDs. The controller syncs pod
# label/namespace selectors to Aviatrix SmartGroups, allowing per-pod DCF rules
# to be defined as Kubernetes resources.
#####################

resource "helm_release" "k8s_firewall" {
  name             = "k8s-firewall"
  repository       = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart            = "k8s-firewall"
  version          = var.k8s_firewall_chart_version
  namespace        = "aviatrix-firewall"
  create_namespace = true
}
