# Thin wrapper: installs the OFFICIAL LibreChat chart onto an existing cluster.
#
# This is optional convenience automation. It references the SAME standalone
# files under chart/ that raw `helm` and ArgoCD use — delete this Terraform and
# you can still `helm install -f chart/values.yaml`. It does NOT manage the
# credentials Secret (kept out of TF state) or the egress FirewallPolicy CRD
# (produced by the generator and applied via kubectl/GitOps). See README.md.

locals {
  values_overlay = file("${path.module}/chart/values.yaml")

  # Inject the standalone librechat.yaml as configYamlContent (equivalent to
  # `helm --set-file librechat.configYamlContent=chart/librechat.yaml`).
  config_overlay = yamlencode({
    librechat = {
      configYamlContent = file("${path.module}/chart/librechat.yaml")
    }
  })
}

# PRECONDITION (create before apply — keeps secrets out of TF state):
#   kubectl -n <namespace> create secret generic librechat-credentials-env \
#     --from-env-file=chart/.env
resource "helm_release" "librechat" {
  name             = var.release_name
  chart            = "oci://ghcr.io/danny-avila/librechat-chart/librechat"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true

  # Later entries win, so config_overlay's configYamlContent takes precedence.
  values = [
    local.values_overlay,
    local.config_overlay,
  ]

  set {
    name  = "ingress.hosts[0].host"
    value = var.ingress_host
  }
}
