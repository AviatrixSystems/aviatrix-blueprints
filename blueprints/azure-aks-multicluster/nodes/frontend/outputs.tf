output "nginx_ingress_lb_ip" {
  description = "Private IP of the NGINX Ingress Controller internal load balancer"
  value       = data.terraform_remote_state.network.outputs.frontend_nginx_lb_ip
}

output "appgw_public_ip" {
  description = "Public IP of the Application Gateway (internet-facing access to Gatus)"
  value       = data.terraform_remote_state.network.outputs.frontend_appgw_public_ip
}

output "pod_masquerade_note" {
  description = "AKS azure-ip-masq-agent already lists 100.64.0.0/16 in NonMasqueradeCIDRs"
  value       = "pod CIDR 100.64.0.0/16 excluded from masquerade by azure-ip-masq-agent"
}
