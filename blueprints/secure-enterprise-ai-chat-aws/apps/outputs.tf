output "librechat_ingress_hostname" {
  description = "LibreChat ALB hostname (public)"
  value       = try(kubernetes_ingress_v1.librechat.status[0].load_balancer[0].ingress[0].hostname, "pending")
}

output "litellm_service" {
  description = "LiteLLM internal service endpoint"
  value       = "${kubernetes_service_v1.litellm.metadata[0].name}.default.svc.cluster.local:4000"
}
