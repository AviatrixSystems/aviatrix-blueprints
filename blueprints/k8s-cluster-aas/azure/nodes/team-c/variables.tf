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
    min_count  = 1
    max_count  = 3
    node_count = 2
    vm_size    = "Standard_D4s_v3"
    priority   = "Spot"
  }
}

variable "controller_ip" {
  description = "IP address or hostname of the Aviatrix Controller"
  type        = string
  default     = null
}

variable "controller_username" {
  description = "Admin username for the Aviatrix Controller"
  type        = string
  default     = "admin"
}

variable "controller_password" {
  description = "Admin password for the Aviatrix Controller"
  type        = string
  sensitive   = true
  default     = null
}
