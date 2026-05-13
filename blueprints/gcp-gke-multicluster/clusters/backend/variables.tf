variable "node_pool_config" {
  description = "Sizing for the primary GKE node pool"
  type = object({
    machine_type  = string
    disk_size_gb  = number
    initial_count = number
    min_count     = number
    max_count     = number
  })
  default = {
    # 2 vCPU, 8 GB — comfortable for Cilium + system pods + Gatus + DCF agent.
    machine_type  = "e2-standard-2"
    disk_size_gb  = 50
    initial_count = 2
    min_count     = 1
    max_count     = 3
  }
}

variable "master_authorized_cidr_blocks" {
  description = <<-EOT
    User CIDR blocks allowed to reach the GKE master endpoint.
    Add your current public IP (e.g., ["1.2.3.4/32"]).
    Use ["0.0.0.0/0"] to allow all (lab only).
    The Aviatrix spoke GW egress IP and (when enable_aviatrix_onboarding=true)
    the Aviatrix Controller IP are appended automatically.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

#####################
# Aviatrix Cluster Onboarding
#####################

variable "enable_aviatrix_onboarding" {
  description = <<-EOT
    Register this GKE cluster with the Aviatrix Controller so DCF SmartGroups
    can target k8s clusters, namespaces, services, and pods.
    When true, the Aviatrix GCP access account's service account needs at
    minimum roles/container.clusterViewer on the project (for getKubeconfig).
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
    Public egress IP of the Aviatrix Controller, appended to GKE
    master_authorized_networks when enable_aviatrix_onboarding = true.
    Required only when master_authorized_cidr_blocks is restrictive; skip
    if you used ["0.0.0.0/0"].
  EOT
  type        = string
  default     = null
}
