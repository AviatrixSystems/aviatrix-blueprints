locals {
  lb_host = local.ingress_enabled ? try(
    coalesce(
      data.kubernetes_ingress_v1.librechat[0].status[0].load_balancer[0].ingress[0].hostname,
      data.kubernetes_ingress_v1.librechat[0].status[0].load_balancer[0].ingress[0].ip,
    ),
    ""
  ) : ""

  chat_url = (
    !local.ingress_enabled ?
    "No ingress class detected. Run: kubectl -n ${var.namespace} port-forward svc/${var.release_name} 3080:3080  then open http://localhost:3080" :
    local.lb_host != "" ?
    "http://${local.lb_host}" :
    "Ingress provisioning. Get the address with: kubectl -n ${var.namespace} get ingress ${var.release_name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  )
}

output "chat_url" {
  description = "Address to open LibreChat: the detected load balancer hostname, or a command to fetch it / port-forward."
  value       = local.chat_url
}

output "irsa_role_arn" {
  description = "ARN of the Bedrock IAM role created for the ServiceAccount (empty when eks_cluster_name is unset)."
  value       = local.role_arn
}

output "detected_ingress_class" {
  description = "Ingress class Terraform auto-detected and installed with (empty = ingress disabled, use port-forward)."
  value       = local.detected_ingress_class
}

output "release_name" {
  description = "Installed Helm release name."
  value       = helm_release.librechat.name
}

output "namespace" {
  description = "Namespace LibreChat was installed into."
  value       = helm_release.librechat.namespace
}

output "chart_version" {
  description = "Version of the official LibreChat chart that was installed."
  value       = helm_release.librechat.version
}

output "pod_label_selector" {
  description = "Label the egress FirewallPolicy must select. Pass to the generator as --pod-label."
  value       = "app.kubernetes.io/name=${helm_release.librechat.name}"
}
