# -----------------------------------------------------------------------------
# Pattern C: GKE Non-Production — Gateway API + ExternalDNS (Cloud DNS)
# -----------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Gateway API CRDs (GKE native support)
# ---------------------------------------------------------------------------

resource "helm_release" "gateway_api" {
  name             = "gateway-api"
  namespace        = "gateway-system"
  create_namespace = true
  repository       = "https://kubernetes-sigs.github.io/gateway-api"
  chart            = "gateway-api"
  version          = "1.0.0"
}

# ---------------------------------------------------------------------------
# ExternalDNS (Cloud DNS + Workload Identity Federation)
# ---------------------------------------------------------------------------

resource "google_service_account" "external_dns" {
  account_id   = "${var.environment_prefix}-np-extdns"
  display_name = "ExternalDNS SA for nonprod cluster"
  project      = var.gcp_project_id
}

resource "google_project_iam_member" "external_dns_dns_admin" {
  project = var.gcp_project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.external_dns.email}"
}

resource "google_service_account_iam_member" "external_dns_workload_identity" {
  service_account_id = google_service_account.external_dns.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[kube-system/external-dns]"
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = "1.14.3"

  set {
    name  = "provider"
    value = "google"
  }

  set {
    name  = "google.project"
    value = var.gcp_project_id
  }

  set {
    name  = "domainFilters[0]"
    value = var.dns_domain
  }

  set {
    name  = "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account"
    value = google_service_account.external_dns.email
  }

  set {
    name  = "txtOwnerId"
    value = "${var.environment_prefix}-nonprod"
  }

  set {
    name  = "policy"
    value = "sync"
  }

  depends_on = [google_service_account_iam_member.external_dns_workload_identity]
}
