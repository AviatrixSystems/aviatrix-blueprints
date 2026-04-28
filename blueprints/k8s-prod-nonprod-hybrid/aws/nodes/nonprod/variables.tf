# No input variables — all values from remote state

variable "controller_ip" {
  description = "IP address or hostname of the Aviatrix Controller"
  type        = string
  default     = null
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
  default     = null
}
