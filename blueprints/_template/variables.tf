# =============================================================================
# Input Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Aviatrix Control Plane
# -----------------------------------------------------------------------------

variable "controller_ip" {
  description = "IP address or hostname of the Aviatrix Controller"
  type        = string
}

variable "controller_username" {
  description = "Admin username for the Aviatrix Controller"
  type        = string
  default     = "admin"
}

variable "controller_password" {
  description = "Admin password for the Aviatrix Controller"
  type        = string
  sensitive   = true
}

variable "aviatrix_account_name" {
  description = "Aviatrix access account name for AWS"
  type        = string
}

# -----------------------------------------------------------------------------
# AWS Configuration
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# Blueprint Configuration
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "blueprint"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "Name prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

# -----------------------------------------------------------------------------
# Gateway Configuration
# -----------------------------------------------------------------------------

variable "gateway_size" {
  description = "Instance size for Aviatrix gateways"
  type        = string
  default     = "t3.medium"
}

# -----------------------------------------------------------------------------
# Optional Features
# -----------------------------------------------------------------------------

# variable "enable_ha" {
#   description = "Enable high availability for gateways"
#   type        = bool
#   default     = false
# }
