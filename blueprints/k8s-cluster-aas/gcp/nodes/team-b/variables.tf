variable "external_dns_chart_version" {
  description = "Helm chart version for ExternalDNS"
  type        = string
  default     = "1.19.0"
}

variable "node_pool_config" {
  description = "Configuration for GKE node pools"
  type = object({
    min_node_count     = number
    max_node_count     = number
    initial_node_count = number
    machine_type       = string
    spot               = bool
  })
  default = {
    min_node_count     = 1
    max_node_count     = 3
    initial_node_count = 1
    machine_type       = "e2-standard-4"
    spot               = true
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
