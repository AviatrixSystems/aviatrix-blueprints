variable "name_prefix" {
  description = "Prefix for all resource names (enables multiple deployments in the same account)"
  type        = string
  default     = "k8s-demo"
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

variable "transit_cidr" {
  description = "CIDR for the Aviatrix transit VPC"
  type        = string
  default     = "10.2.0.0/20"
}

variable "frontend_vpc_cidr" {
  description = "Primary CIDR for the frontend EKS VPC"
  type        = string
  default     = "10.10.0.0/23"
}

variable "backend_vpc_cidr" {
  description = "Primary CIDR for the backend EKS VPC"
  type        = string
  default     = "10.20.0.0/23"
}

variable "db_vpc_cidr" {
  description = "CIDR for the database spoke VPC"
  type        = string
  default     = "10.5.0.0/22"
}

variable "pod_cidr" {
  description = "Secondary CIDR for pod networking (overlapping across VPCs, RFC6598)"
  type        = string
  default     = "100.64.0.0/16"
}
