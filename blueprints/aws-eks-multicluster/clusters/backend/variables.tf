variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-2"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.34"
}

variable "aviatrix_controller_role_arn" {
  description = "IAM role ARN used by Aviatrix Controller to access EKS clusters (e.g., arn:aws:iam::ACCOUNT_ID:role/aviatrix-role-app)"
  type        = string
}
