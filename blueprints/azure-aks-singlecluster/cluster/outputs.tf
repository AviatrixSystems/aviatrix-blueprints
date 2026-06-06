output "cluster_id" {
  value = module.cluster.cluster_id
}

output "cluster_name" {
  value = module.cluster.cluster_name
}

output "oidc_issuer_url" {
  value = module.cluster.oidc_issuer_url
}

output "host" {
  value     = module.cluster.host
  sensitive = true
}

output "client_certificate" {
  value     = module.cluster.client_certificate
  sensitive = true
}

output "client_key" {
  value     = module.cluster.client_key
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = module.cluster.cluster_ca_certificate
  sensitive = true
}

output "configure_kubectl" {
  value = module.cluster.configure_kubectl
}
