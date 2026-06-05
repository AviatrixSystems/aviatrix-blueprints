variable "kubernetes_version" {
  description = "AKS Kubernetes version."
  type        = string
  default     = "1.33"
}

variable "node_pool_config" {
  description = "AKS system node pool sizing."
  type = object({
    node_count = number
    min_count  = number
    max_count  = number
    vm_size    = string
  })
  default = {
    node_count = 2
    min_count  = 1
    max_count  = 3
    vm_size    = "Standard_B2s"
  }
}

variable "authorized_ip_ranges" {
  description = "Extra CIDRs allowed to reach the AKS API server."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_aviatrix_onboarding" {
  description = "Register the AKS cluster with the Aviatrix Controller for K8s SmartGroups."
  type        = bool
  default     = true
}

variable "aviatrix_controller_public_ip" {
  description = "Controller public egress IP for AKS API allowlist when onboarding."
  type        = string
  default     = null
}

variable "aviatrix_controller_ip" {
  description = "Aviatrix Controller IP/hostname."
  type        = string
}

variable "aviatrix_username" {
  description = "Aviatrix Controller username."
  type        = string
}

variable "aviatrix_password" {
  description = "Aviatrix Controller password."
  type        = string
  sensitive   = true
}
