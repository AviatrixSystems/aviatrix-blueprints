#####################
# NGINX Ingress Controller (internal Azure LB in the ingress subnet)
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
          loadBalancerIP = var.nginx_lb_ip
          annotations = {
            "service.beta.kubernetes.io/azure-load-balancer-internal"        = "true"
            "service.beta.kubernetes.io/azure-load-balancer-internal-subnet" = local.net.ingress_subnet_name
            "service.beta.kubernetes.io/azure-load-balancer-ip-address"      = var.nginx_lb_ip
          }
        }
        metrics = { enabled = true }
      }
    })
  ]
}

#####################
# Aviatrix K8s Firewall (DCF CRD controller)
#####################
resource "helm_release" "k8s_firewall" {
  name             = "k8s-firewall"
  repository       = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart            = "k8s-firewall"
  version          = var.k8s_firewall_chart_version
  namespace        = "aviatrix-firewall"
  create_namespace = true
}
