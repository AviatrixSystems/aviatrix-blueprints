variable "azure_region" {
  description = "Azure region in azurerm format (e.g., 'eastus2')"
  type        = string
  default     = "eastus2"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster (avoid LTS-only versions like 1.32 unless on Premium tier)"
  type        = string
  default     = "1.33"
}

variable "node_pool_config" {
  description = "Configuration for the default system node pool"
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
    # B-series chosen so AKS nodes don't compete with the 4 Aviatrix gateways
    # for the DSv3 vCPU quota in eastus2 (default 10). B-series is also a
    # better fit for bursty lab workloads (NGINX, Gatus, sys pods).
    vm_size = "Standard_B2s"
  }
}

variable "authorized_ip_ranges" {
  description = <<-EOT
    IP ranges authorized to access the AKS API server.
    Add your current public IP (e.g., ["1.2.3.4/32"]).
    Use ["0.0.0.0/0"] to allow all (not recommended for production).
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
