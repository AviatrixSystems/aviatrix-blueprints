variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "zt-seg"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_name" {
  description = "Aviatrix Access Account name for AWS"
  type        = string
}

variable "transit_gateway" {
  description = "Transit gateway configuration"
  type = object({
    cidr       = string
    asn        = number
    ha_enabled = bool
  })
  default = {
    cidr       = "10.0.0.0/23"
    asn        = 64512
    ha_enabled = false
  }
}

variable "spokes" {
  description = "Spoke gateway configurations"
  type = map(object({
    cidr        = string
    environment = string
  }))
  default = {
    dev = {
      cidr        = "10.1.0.0/24"
      environment = "development"
    }
    prod = {
      cidr        = "10.2.0.0/24"
      environment = "production"
    }
    db = {
      cidr        = "10.3.0.0/24"
      environment = "database"
    }
  }
}

variable "test_vm_instance_type" {
  description = "EC2 instance type for test VMs"
  type        = string
  default     = "t3.micro"
}

variable "test_vm_key_name" {
  description = "EC2 key pair name for SSH access to test VMs"
  type        = string
}
