variable "external_dns_chart_version" {
  description = "ExternalDNS Helm chart version (must support gateway-httproute source — chart >= 1.14)"
  type        = string
  default     = "1.15.0"
}

variable "k8s_firewall_chart_version" {
  description = "Aviatrix k8s-firewall Helm chart version (8.2.0 or 9.0.0 — published in https://aviatrixsystems.github.io/k8s-firewall-charts/index.yaml)"
  type        = string
  default     = "9.0.0"
}
