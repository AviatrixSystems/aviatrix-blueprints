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
