# -----------------------------------------------------------------------------
# Pattern C: AKS Production — nginx-ingress + ExternalDNS (Azure Private DNS)
# -----------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# nginx-ingress Controller
# ---------------------------------------------------------------------------

resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.9.1"

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-internal"
    value = "true"
  }

  set {
    name  = "controller.replicaCount"
    value = "2"
  }

  set {
    name  = "controller.nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }
}

# ---------------------------------------------------------------------------
# ExternalDNS (Azure Private DNS + Workload Identity)
# ---------------------------------------------------------------------------

resource "helm_release" "external_dns" {
  name             = "external-dns"
  namespace        = "kube-system"
  repository       = "https://kubernetes-sigs.github.io/external-dns"
  chart            = "external-dns"
  version          = "1.14.3"

  set {
    name  = "provider"
    value = "azure-private-dns"
  }

  set {
    name  = "azure.resourceGroup"
    value = var.dns_zone_resource_group
  }

  set {
    name  = "azure.subscriptionId"
    value = data.azurerm_subscription.current.subscription_id
  }

  set {
    name  = "azure.tenantId"
    value = data.azurerm_client_config.current.tenant_id
  }

  set {
    name  = "azure.useWorkloadIdentityExtension"
    value = "true"
  }

  set {
    name  = "domainFilters[0]"
    value = var.dns_zone_name
  }

  set {
    name  = "txtOwnerId"
    value = "${var.environment_prefix}-prod"
  }

  set {
    name  = "policy"
    value = "sync"
  }
}
