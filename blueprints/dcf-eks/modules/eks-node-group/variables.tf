variable "cluster_name" {
  description = "Name of the EKS cluster to attach node group to"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version of the cluster (for AMI selection)"
  type        = string
}

variable "node_group_name" {
  description = "Name suffix for the node group"
  type        = string
  default     = "default"
}

variable "subnet_ids" {
  description = "Subnet IDs where nodes will be launched"
  type        = list(string)
}

variable "cluster_primary_security_group_id" {
  description = "EKS cluster primary security group ID (from cluster outputs)"
  type        = string
}

variable "cluster_service_cidr" {
  description = "Kubernetes service CIDR for the cluster"
  type        = string
  default     = ""
}

variable "min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 3
}

variable "desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "instance_types" {
  description = "List of instance types for the node group"
  type        = list(string)
  default     = ["t3.large"]
}

variable "capacity_type" {
  description = "Capacity type: ON_DEMAND or SPOT"
  type        = string
  default     = "SPOT"
}

variable "ami_type" {
  description = "AMI type for nodes (AL2_x86_64, AL2023_x86_64_STANDARD, etc.)"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "labels" {
  description = "Kubernetes labels to apply to nodes"
  type        = map(string)
  default     = {}
}

variable "taints" {
  description = "Kubernetes taints to apply to nodes"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
