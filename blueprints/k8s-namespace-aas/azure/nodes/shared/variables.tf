variable "nginx_ingress_chart_version" {
  description = "Helm chart version for nginx-ingress controller"
  type        = string
  default     = "4.11.0"
}

variable "external_dns_chart_version" {
  description = "Helm chart version for ExternalDNS"
  type        = string
  default     = "1.15.0"
}

variable "node_pool_config" {
  description = "Configuration for AKS user node pools"
  type = object({
    min_count  = number
    max_count  = number
    node_count = number
    vm_size    = string
    priority   = string
  })
  default = {
    min_count  = 2
    max_count  = 6
    node_count = 3
    vm_size    = "Standard_D4s_v3"
    priority   = "Spot"
  }
}
