variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "k8s-demo"
}

variable "subnet_id" {
  description = "Subnet ID for the VM instance"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "vpc_id" {
  description = "VPC ID for the security group"
  type        = string
}

variable "eice_security_group_ids" {
  description = "Security group IDs of the EC2 Instance Connect Endpoint"
  type        = list(string)
  default     = []
}