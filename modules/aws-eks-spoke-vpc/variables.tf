variable "name" {
  description = "Name prefix for all resources in this spoke (e.g. \"frontend\", \"team-a\"). Used directly in resource names and tags."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name. Used to tag subnets with kubernetes.io/cluster/<name>=shared so EKS auto-discovery works for LB/Ingress placement."
  type        = string
}

variable "primary_cidr" {
  description = "Primary VPC CIDR. Subnet math assumes /23 and produces /28 Aviatrix-gateway, /26 load-balancer, /26 infrastructure subnets per AZ. Override at your own risk -- a different prefix length shifts all subnet sizes."
  type        = string

  validation {
    condition     = can(cidrhost(var.primary_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block."
  }
}

variable "pod_cidr" {
  description = "Secondary CIDR for pod networking (VPC CNI custom networking). Can overlap across spokes -- Aviatrix custom SNAT translates pod IPs to the spoke gateway IP before traffic leaves the VPC."
  type        = string
  default     = "100.64.0.0/16"
}

variable "region" {
  description = "AWS region. Availability zones are derived as <region>a and <region>b."
  type        = string
}

variable "aviatrix_aws_account_name" {
  description = "AWS account name as registered in the Aviatrix Controller."
  type        = string
}

variable "transit_type" {
  description = "How this spoke reaches other VPCs. One of \"aviatrix\" (attach to an Aviatrix transit gateway), \"aws_tgw\" (AWS Transit Gateway), or \"aws_cloudwan\" (AWS Cloud WAN). Drives SNAT shape and route-table programming."
  type        = string
  default     = "aws_tgw"

  validation {
    condition     = contains(["aviatrix", "aws_tgw", "aws_cloudwan"], var.transit_type)
    error_message = "transit_type must be one of: aviatrix, aws_tgw, aws_cloudwan."
  }
}

variable "pod_cidr_mode" {
  description = "Whether pod IPs are routable across the fabric. \"non_routable\" (default) forces all pod egress through the spoke gateway for SNAT; \"routable\" lets pods take the native-cloud transit path directly for east-west."
  type        = string
  default     = "non_routable"

  validation {
    condition     = contains(["routable", "non_routable"], var.pod_cidr_mode)
    error_message = "pod_cidr_mode must be one of: routable, non_routable."
  }
}

variable "transit_gw_name" {
  description = "Aviatrix transit gateway name to attach this spoke to. Required iff transit_type = \"aviatrix\"."
  type        = string
  default     = ""
}

variable "aws_tgw_id" {
  description = "AWS Transit Gateway ID (e.g. tgw-0abc...). Optional even when transit_type = \"aws_tgw\": leave empty for the standalone-spoke case (attachment + routes wired out-of-band). Must be empty for other transit types."
  type        = string
  default     = ""
}

variable "aws_cloudwan_core_network_arn" {
  description = "AWS Cloud WAN Core Network ARN. Optional even when transit_type = \"aws_cloudwan\" (standalone case). Must be empty for other transit types."
  type        = string
  default     = ""
}

variable "east_west_cidrs" {
  description = "East-west destination CIDRs programmed on the spoke route tables when transit_type is aws_tgw or aws_cloudwan."
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

variable "additional_cluster_names" {
  description = "Extra cluster names to add as kubernetes.io/cluster/<name>=shared subnet tags, for multi-cluster-per-VPC patterns. The primary cluster_name is always tagged."
  type        = list(string)
  default     = []
}

variable "spoke_instance_size" {
  description = "EC2 instance type for the Aviatrix spoke gateway."
  type        = string
  default     = "t3.medium"
}

variable "spoke_ha_gw" {
  description = "Whether to deploy an HA spoke gateway."
  type        = bool
  default     = false
}

variable "enable_vpc_dns_server" {
  description = "Use the VPC DNS server for gateway management. Required for hostname SmartGroups and resolving Route53 private hosted zones from the gateway."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}

# NOTE: the cross-field transit-input consistency rule (which target inputs are
# allowed per transit_type) is enforced by a lifecycle precondition on
# aws_vpc.this in main.tf, not a variable validation -- variable validations
# that reference other variables require Terraform >= 1.9, but this module
# targets >= 1.5. Preconditions (>= 1.2) can reference multiple variables.
