variable "name_prefix" {
  description = "Prefix for all resource names (e.g., 'gke-demo')"
  type        = string
  default     = "gke-demo"
}

# Aviatrix Controller credentials. Referenced by the aviatrix provider block so
# `terraform validate` passes without env vars set. At plan/apply time, leave
# these empty in tfvars and export AVIATRIX_CONTROLLER_IP / AVIATRIX_USERNAME /
# AVIATRIX_PASSWORD env vars instead.
variable "aviatrix_controller_ip" {
  description = "Aviatrix Controller IP/hostname. Leave null and export AVIATRIX_CONTROLLER_IP instead."
  type        = string
  default     = null
}

variable "aviatrix_username" {
  description = "Aviatrix Controller username. Leave null and export AVIATRIX_USERNAME instead."
  type        = string
  default     = null
}

variable "aviatrix_password" {
  description = "Aviatrix Controller password. Leave null and export AVIATRIX_PASSWORD instead."
  type        = string
  sensitive   = true
  default     = null
}

variable "aviatrix_gcp_account_name" {
  description = "Aviatrix access account name for GCP (configured in Controller — typically 'Google')"
  type        = string
}

variable "gcp_project_id" {
  description = "GCP project that owns the VPCs, GKE clusters, and DB VM"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for subnets and zonal resources (e.g., 'us-central1')"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone for zonal GKE clusters and the DB VM (e.g., 'us-central1-a')"
  type        = string
  default     = "us-central1-a"
}

variable "transit_cidr" {
  description = "CIDR for the Aviatrix Transit VPC"
  type        = string
  default     = "10.2.0.0/24"
}

variable "gw_instance_size" {
  description = <<-EOT
    GCE machine type for the Aviatrix transit + spoke gateways. Default
    n1-standard-1 (~1 Gbps) is sized for lab demos. Step up to n1-standard-4 or
    higher for bandwidth-heavy workloads. Same size is applied to all four GWs
    (transit + frontend + backend + db spokes).
  EOT
  type        = string
  default     = "n1-standard-1"
}

variable "frontend_vpc_cidr" {
  description = "Aggregate CIDR documented for the frontend VPC (used in firewall rules; subnets are carved from it)"
  type        = string
  default     = "10.10.0.0/20"
}

variable "frontend_nodes_cidr" {
  description = "Primary CIDR for the frontend GKE node subnet"
  type        = string
  default     = "10.10.0.0/22"
}

variable "frontend_avx_gw_cidr" {
  description = "Aviatrix spoke GW subnet CIDR for frontend"
  type        = string
  default     = "10.10.4.0/28"
}

variable "frontend_proxy_only_cidr" {
  description = "Regional proxy-only subnet CIDR for frontend (used by GCP-managed L7 ALB / Gateway API)"
  type        = string
  default     = "10.10.5.0/24"
}

variable "frontend_master_cidr" {
  description = "GKE control-plane CIDR (/28) for the frontend cluster"
  type        = string
  default     = "172.20.0.0/28"
}

variable "backend_vpc_cidr" {
  description = "Aggregate CIDR documented for the backend VPC"
  type        = string
  default     = "10.20.0.0/20"
}

variable "backend_nodes_cidr" {
  description = "Primary CIDR for the backend GKE node subnet"
  type        = string
  default     = "10.20.0.0/22"
}

variable "backend_avx_gw_cidr" {
  description = "Aviatrix spoke GW subnet CIDR for backend"
  type        = string
  default     = "10.20.4.0/28"
}

variable "backend_proxy_only_cidr" {
  description = "Regional proxy-only subnet CIDR for backend"
  type        = string
  default     = "10.20.5.0/24"
}

variable "backend_master_cidr" {
  description = "GKE control-plane CIDR (/28) for the backend cluster"
  type        = string
  default     = "172.20.1.0/28"
}

variable "db_vpc_cidr" {
  description = "Aggregate CIDR for the DB test VPC"
  type        = string
  default     = "10.5.0.0/22"
}

variable "db_subnet_cidr" {
  description = "Primary subnet CIDR for the DB test VM"
  type        = string
  default     = "10.5.0.0/24"
}

variable "db_avx_gw_cidr" {
  description = "Aviatrix spoke GW subnet CIDR for the DB VPC"
  type        = string
  default     = "10.5.1.0/28"
}

variable "frontend_pods_cidr" {
  description = <<-EOT
    Pod alias range for the frontend GKE cluster. Defaults to 100.64.0.0/16
    (overlaps with backend by design — Aviatrix spoke GW SNATs pod IPs at the
    transit edge so the overlap is invisible east-west).

    NOTE: pod-CIDR-overlap east-west between clusters does NOT currently work
    on GCP with `single_ip_snat = true` (which only SNATs internet egress; the
    transit path leaves pod source IPs unchanged, colliding with the
    destination cluster's identical /16). For working east-west between two
    GKE clusters, set non-overlapping CIDRs here and in backend_pods_cidr
    BEFORE first apply (existing alias ranges cannot be modified in-place
    once GKE pods have allocated IPs from them).
  EOT
  type        = string
  default     = "100.64.0.0/16"
}

variable "backend_pods_cidr" {
  description = "Pod alias range for the backend GKE cluster. See frontend_pods_cidr docstring."
  type        = string
  default     = "100.64.0.0/16"
}

variable "services_cidr" {
  description = "GKE Services secondary range — overlapping by design (kube-internal, never leaves the cluster)"
  type        = string
  default     = "172.16.0.0/20"
}

variable "private_dns_zone_name" {
  description = "Cloud DNS private zone DNS name (must end with '.')"
  type        = string
  default     = "gcp.aviatrixdemo.local."
}

variable "enable_k8s_smartgroup_demo" {
  description = <<-EOT
    Create K8s-typed SmartGroups (per-cluster + per-namespace) and the
    priority-50 demo DCF rule that references them.

    DESTROY WORKFLOW: set this to false and `terraform apply` BEFORE destroying
    clusters/{frontend,backend}. The aviatrix_kubernetes_cluster registration
    cannot be deleted while these SmartGroups reference its cluster_id.
  EOT
  type        = bool
  default     = true
}
