variable "name_prefix" {
  description = "Prefix for all resource names (enables multiple deployments in the same account)"
  type        = string
  default     = "ai-chat"
}

variable "aviatrix_aws_account_name" {
  description = "AWS account name as registered in Aviatrix Controller"
  type        = string
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-2"
}

variable "vpc_cidr" {
  description = "CIDR for the application VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "transit_cidr" {
  description = "CIDR for the Aviatrix transit VPC"
  type        = string
  default     = "10.0.0.0/20"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "node_group_config" {
  description = "Configuration for EKS managed node group"
  type = object({
    min_size       = number
    max_size       = number
    desired_size   = number
    instance_types = list(string)
    capacity_type  = string
  })
  default = {
    min_size       = 2
    max_size       = 4
    desired_size   = 2
    instance_types = ["t3.large"]
    capacity_type  = "ON_DEMAND"
  }
}

variable "aviatrix_controller_role_arn" {
  description = "IAM role ARN of the Aviatrix Controller (for EKS access entry). Leave empty to skip onboarding."
  type        = string
  default     = ""
}
