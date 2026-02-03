variable "aviatrix_aws_account_name" {
  description = "AWS account name as registered in Aviatrix Controller"
  type        = string
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-2"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS clusters"
  type        = string
  default     = "1.33"
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

variable "route53_private_zone_name" {
  description = "Route53 private hosted zone name for internal DNS"
  type        = string
  default     = "aws.aviatrixdemo.local"
}
