output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.this.name
}

output "cluster_endpoint" {
  description = "GKE cluster API server endpoint (without https://)"
  value       = google_container_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64 encoded CA certificate for the GKE cluster"
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "GKE cluster region or zone"
  value       = google_container_cluster.this.location
}

output "external_dns_service_account_email" {
  description = "GCP service account email for ExternalDNS Workload Identity"
  value       = google_service_account.external_dns.email
}

output "external_dns_helm_values" {
  description = "Pre-rendered Helm values for ExternalDNS with Workload Identity annotations"
  value = yamlencode({
    provider = { name = "google" }
    google   = { project = local.gcp_project }
    serviceAccount = {
      create = true
      name   = "external-dns"
      annotations = {
        "iam.gke.io/gcp-service-account" = google_service_account.external_dns.email
      }
    }
    sources       = ["service", "ingress", "gateway-httproute", "gateway-tlsroute"]
    domainFilters = [local.dns_zone_name]
    policy        = "sync"
    txtOwnerId    = google_container_cluster.this.name
    extraArgs = [
      "--google-project=${local.gcp_project}",
      "--google-zone-visibility=private",
    ]
  })
}

output "cluster_id" {
  description = "GKE cluster self-link — consumed by aviatrix_kubernetes_cluster and DCF SmartGroups"
  value       = google_container_cluster.this.self_link
}
