variable "azure_region" {
  description = "Azure region in azurerm format (e.g., 'eastus2')"
  type        = string
  default     = "eastus2"
}

variable "nginx_ingress_chart_version" {
  description = "NGINX Ingress Controller Helm chart version"
  type        = string
  default     = "4.12.0"
}

variable "external_dns_chart_version" {
  description = "ExternalDNS Helm chart version"
  type        = string
  default     = "1.15.0"
}

variable "k8s_firewall_chart_version" {
  description = "Aviatrix k8s-firewall Helm chart version (DCF CRD controller)"
  type        = string
  default     = "8.2.0"
}
