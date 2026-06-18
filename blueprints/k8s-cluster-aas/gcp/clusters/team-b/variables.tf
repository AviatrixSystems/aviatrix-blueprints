variable "release_channel" {
  type    = string
  default = "REGULAR"
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [{ cidr_block = "0.0.0.0/0", display_name = "All (restrict in production)" }]
}
