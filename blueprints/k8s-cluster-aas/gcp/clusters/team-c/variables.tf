variable "release_channel" {
  description = "GKE release channel for automatic upgrades (RAPID, REGULAR, or STABLE)"
  type        = string
  default     = "REGULAR"
}

variable "master_authorized_networks" {
  description = "List of CIDR blocks authorized to reach the GKE control plane"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [{ cidr_block = "0.0.0.0/0", display_name = "All (restrict in production)" }]
}
