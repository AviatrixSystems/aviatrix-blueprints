variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-2"
}

variable "alb_controller_chart_version" {
  description = "Helm chart version for AWS Load Balancer Controller"
  type        = string
  default     = "1.10.1"
}

variable "k8s_firewall_chart_version" {
  description = "Helm chart version for the Aviatrix k8s-firewall DCF CRDs"
  type        = string
  default     = "9.0.0"
}

variable "node_group_config" {
  description = "Configuration for EKS managed node groups"
  type = object({
    min_size       = number
    max_size       = number
    desired_size   = number
    instance_types = list(string)
    capacity_type  = string
  })
  default = {
    min_size       = 1
    max_size       = 3
    desired_size   = 2
    instance_types = ["t3.large"]
    capacity_type  = "SPOT"
  }
}
