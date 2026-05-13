#####################
# NGINX Ingress Controller
# Provides L7 ingress for services in the backend cluster.
# Creates an internal Azure Load Balancer at a static private IP in the system subnet.
# AppGW (internet-facing) forwards traffic to this internal LB — response traffic is
# VNet-internal (AppGW → NGINX → AppGW → client), avoiding asymmetric routing
# through the Aviatrix UDR.
#####################

resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.nginx_ingress_chart_version
  namespace        = "ingress-nginx"
  create_namespace = true

  values = [
    yamlencode({
      controller = {
        service = {
          # Static private IP in the system subnet (10.20.0.128/25).
          # AppGW backend pool targets this IP. Response traffic is VNet-internal
          # (AppGW → NGINX LB → AppGW → client), avoiding asymmetric routing through Aviatrix.
          loadBalancerIP = data.terraform_remote_state.network.outputs.backend_nginx_lb_ip
          annotations = {
            "service.beta.kubernetes.io/azure-load-balancer-internal"        = "true"
            "service.beta.kubernetes.io/azure-load-balancer-internal-subnet" = "backend-system"
            "service.beta.kubernetes.io/azure-load-balancer-ip-address"      = data.terraform_remote_state.network.outputs.backend_nginx_lb_ip
          }
        }
        metrics = {
          enabled = true
        }
      }
    })
  ]


}

#####################
# ExternalDNS (Azure Private DNS)
# Automatically creates DNS records in the Azure Private DNS zone
# for services/ingresses with the correct annotations.
#
# Uses Workload Identity — no credentials stored in the cluster.
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
        name = "azure-private-dns"
      }

      # ExternalDNS azure-private-dns provider requires /etc/kubernetes/azure.json
      # even when using Workload Identity. secretConfiguration creates the Secret
      # and mounts it at the specified path automatically.
      secretConfiguration = {
        enabled   = true
        mountPath = "/etc/kubernetes"
        data = {
          "azure.json" = jsonencode({
            tenantId                     = data.azurerm_client_config.current.tenant_id
            subscriptionId               = data.azurerm_client_config.current.subscription_id
            resourceGroup                = data.terraform_remote_state.network.outputs.dns_resource_group_name
            useWorkloadIdentityExtension = true
            userAssignedIdentityID       = data.terraform_remote_state.cluster.outputs.external_dns_client_id
          })
        }
      }

      serviceAccount = {
        create = true
        name   = "external-dns"
        annotations = {
          "azure.workload.identity/client-id" = data.terraform_remote_state.cluster.outputs.external_dns_client_id
        }
      }

      podLabels = {
        "azure.workload.identity/use" = "true"
      }

      txtOwnerId = local.cluster_name
      txtPrefix  = "${local.cluster_name}-"

      # Only manage records in our private DNS zone
      domainFilters = [local.dns_zone_name]

      # sync: creates and deletes records; upsert-only: only creates
      policy = "sync"

      # Filter to services and ingresses with ExternalDNS annotations
      sources = ["service", "ingress"]

      logLevel = "info"
    })
  ]


}

#####################
# Aviatrix K8s Firewall (DCF CRD Controller)
# Enables FirewallPolicy and WebGroupPolicy CRDs in the cluster.
# The controller syncs pod label/namespace selectors to Aviatrix SmartGroups,
# allowing per-pod DCF rules to be defined as Kubernetes resources.
#####################

resource "helm_release" "k8s_firewall" {
  name             = "k8s-firewall"
  repository       = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart            = "k8s-firewall"
  version          = var.k8s_firewall_chart_version
  namespace        = "aviatrix-firewall"
  create_namespace = true


}
