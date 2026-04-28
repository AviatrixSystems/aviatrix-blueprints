variable "node_group_config" {
  description = "Configuration for EKS managed node groups"
  type = object({
    min_size      = number
    max_size      = number
    desired_size  = number
    instance_type = string
    capacity_type = string
  })
  default = {
    min_size      = 1
    max_size      = 3
    desired_size  = 2
    instance_type = "t3.large"
    capacity_type = "SPOT"
  }
}

variable "alb_controller_chart_version" {
  description = "Helm chart version for AWS ALB Controller"
  type        = string
  default     = "1.8.0"
}

variable "external_dns_chart_version" {
  description = "Helm chart version for ExternalDNS"
  type        = string
  default     = "1.15.0"
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
