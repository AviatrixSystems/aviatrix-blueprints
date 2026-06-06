output "nginx_ingress_namespace" {
  value = helm_release.nginx_ingress.namespace
}

output "nginx_lb_ip" {
  value = var.nginx_lb_ip
}

output "k8s_firewall_namespace" {
  value = helm_release.k8s_firewall.namespace
}
