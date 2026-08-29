variable "kubernetes_version" {
  description = "Kubernetes version for the shared AKS cluster"
  type        = string
  default     = "1.35"
}

variable "system_node_vm_size" {
  description = "VM size for the AKS system node pool (runs critical add-ons only)"
  type        = string
  default     = "Standard_B2s"
}
