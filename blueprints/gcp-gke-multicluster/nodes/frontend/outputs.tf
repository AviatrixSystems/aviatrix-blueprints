output "external_dns_namespace" {
  description = "Kubernetes namespace where the ExternalDNS Helm release was installed."
  value       = helm_release.external_dns.namespace
}

output "k8s_firewall_namespace" {
  description = "Kubernetes namespace where the Aviatrix k8s-firewall Helm release was installed."
  value       = helm_release.k8s_firewall.namespace
}
