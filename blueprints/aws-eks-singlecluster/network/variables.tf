variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
  default     = "eks-singlecluster"
}

variable "aviatrix_aws_account_name" {
  description = "AWS account name as registered in the Aviatrix Controller."
  type        = string
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-2"
}

variable "vpc_cidr" {
  description = "Primary VPC CIDR (chosen to avoid multicluster's 10.10/10.20/10.5 defaults)."
  type        = string
  default     = "10.30.0.0/23"
}

variable "pod_cidr" {
  description = "Secondary CIDR for pod networking."
  type        = string
  default     = "100.64.0.0/16"
}

variable "transit_type" {
  description = "Spoke transit mode: aviatrix | aws_tgw | aws_cloudwan."
  type        = string
  default     = "aws_tgw"
}

variable "pod_cidr_mode" {
  description = "routable | non_routable."
  type        = string
  default     = "non_routable"
}

variable "transit_gw_name" {
  description = "Aviatrix transit gateway name (only when transit_type = aviatrix)."
  type        = string
  default     = ""
}

variable "aws_tgw_id" {
  description = "AWS TGW ID to attach E-W routes to (only when transit_type = aws_tgw). Empty = standalone."
  type        = string
  default     = ""
}

variable "aws_cloudwan_core_network_arn" {
  description = "AWS Cloud WAN Core Network ARN (only when transit_type = aws_cloudwan). Empty = standalone."
  type        = string
  default     = ""
}
