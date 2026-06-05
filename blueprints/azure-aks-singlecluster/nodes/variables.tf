variable "nginx_ingress_chart_version" {
  type    = string
  default = "4.11.3"
}

variable "k8s_firewall_chart_version" {
  type    = string
  default = "1.0.0"
}

variable "nginx_lb_ip" {
  description = "Static private IP for the internal NGINX LB (must be inside the ingress subnet, outside Azure-reserved first 4 hosts)."
  type        = string
  default     = "10.30.0.200"
}
