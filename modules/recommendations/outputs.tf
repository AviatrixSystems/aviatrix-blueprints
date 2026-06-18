# ─────────────────────────────────────────────────────────────────────────────
# Module Outputs — Report which recommendations are active
# ─────────────────────────────────────────────────────────────────────────────

output "enabled_recommendations" {
  description = "Map of recommendation toggle states"
  value = {
    network_policy           = var.enable_network_policy
    gatekeeper               = var.enable_gatekeeper
    external_secrets         = var.enable_external_secrets
    falco                    = var.enable_falco
    prometheus_stack         = var.enable_prometheus_stack
    fluent_bit               = var.enable_fluent_bit
    node_termination_handler = var.enable_node_termination_handler
    cluster_autoscaler       = var.enable_cluster_autoscaler
    velero                   = var.enable_velero
  }
}

output "velero_bucket_name" {
  description = "S3 bucket name for Velero backups (empty if Velero disabled)"
  value       = var.enable_velero ? aws_s3_bucket.velero[0].id : ""
}
