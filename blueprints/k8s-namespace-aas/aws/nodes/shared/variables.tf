variable "node_group_config" {
  description = "Configuration for EKS managed node group"
  type = object({
    min_size      = number
    max_size      = number
    desired_size  = number
    instance_type = string
    capacity_type = string
  })
  default = {
    min_size      = 2
    max_size      = 6
    desired_size  = 3
    instance_type = "m5.xlarge"
    capacity_type = "SPOT"
  }
}

variable "alb_controller_chart_version" {
  description = "Helm chart version for AWS Load Balancer Controller"
  type        = string
  default     = "1.8.0"
}

variable "external_dns_chart_version" {
  description = "Helm chart version for ExternalDNS"
  type        = string
  default     = "1.15.0"
}
