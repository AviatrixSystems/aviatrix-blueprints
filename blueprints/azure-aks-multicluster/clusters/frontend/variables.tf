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
    NOTE: when enable_aviatrix_onboarding = true, the Aviatrix Controller's
    public egress IP must also be in this list, OR set
    aviatrix_controller_public_ip and it will be appended automatically.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

#####################
# Aviatrix Cluster Onboarding
#####################

variable "enable_aviatrix_onboarding" {
  description = <<-EOT
    Register this AKS cluster with the Aviatrix Controller so DCF SmartGroups
    can target k8s clusters, namespaces, services, and pods.
    When true, requires the Aviatrix Azure access account to have the
    Microsoft.ContainerService/managedClusters/listClusterUserCredential/action
    permission at subscription scope (Contributor includes it).
  EOT
  type        = bool
  default     = true
}

variable "aviatrix_controller_ip" {
  description = "Aviatrix Controller IP/hostname (or set AVIATRIX_CONTROLLER_IP env var)"
  type        = string
  default     = null
}

variable "aviatrix_username" {
  description = "Aviatrix Controller username (or set AVIATRIX_USERNAME env var)"
  type        = string
  default     = null
}

variable "aviatrix_password" {
  description = "Aviatrix Controller password (or set AVIATRIX_PASSWORD env var)"
  type        = string
  sensitive   = true
  default     = null
}

variable "aviatrix_controller_public_ip" {
  description = <<-EOT
    Public IP of the Aviatrix Controller, appended to AKS authorized_ip_ranges
    when enable_aviatrix_onboarding = true. The controller fetches the AKS
    kubeconfig via ARM, then connects to the AKS API server FQDN — that
    second hop must clear the API server allowlist. Leave null if your
    authorized_ip_ranges already covers the controller (e.g., 0.0.0.0/0).
  EOT
  type        = string
  default     = null
}
