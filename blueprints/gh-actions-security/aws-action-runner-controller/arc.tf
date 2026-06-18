locals {
  # Helm release names — deployment_id suffix prevents collisions when
  # multiple instances of this blueprint share the same EKS cluster.
  arc_controller_release = "arc-${random_integer.deployment_id.result}"
  arc_scaleset_release   = "arc-ss-${random_integer.deployment_id.result}"
}

# ARC controller — installs the actions-runner-controller operator into the
# arc-systems namespace.
resource "helm_release" "arc_controller" {
  name             = local.arc_controller_release
  repository       = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart            = "gha-runner-scale-set-controller"
  namespace        = "arc-systems"
  create_namespace = true

  wait    = true
  timeout = 300

  depends_on = [aviatrix_distributed_firewalling_policy_list.runner]
}

# Runner scale set — runner pods land in the arc-runners namespace.
resource "helm_release" "arc_runner_scaleset" {
  name             = local.arc_scaleset_release
  repository       = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart            = "gha-runner-scale-set"
  namespace        = "arc-runners"
  create_namespace = true

  wait    = true
  timeout = 300

  set {
    name  = "githubConfigUrl"
    value = var.github_repo_url
  }

  set_sensitive {
    name  = "githubConfigSecret.github_token"
    value = var.github_pat
  }

  set {
    name  = "runnerScaleSetName"
    value = var.arc_runner_name
  }

  set {
    name  = "minRunners"
    value = "0"
  }

  set {
    name  = "maxRunners"
    value = "5"
  }

  depends_on = [
    helm_release.arc_controller,
    aviatrix_distributed_firewalling_policy_list.runner,
  ]
}

# ---------------------------------------------------------------------------
# TLS-decryption probe — dedicated namespace for its own k8s SmartGroup and
# a DCF rule with decrypt_policy=DECRYPT_ALLOWED.
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "tls_probe" {
  count = var.deploy_probes ? 1 : 0
  metadata {
    name = "arc-tls-probe"
  }
}

resource "kubernetes_secret" "aviatrix_ca" {
  count = var.deploy_probes ? 1 : 0
  metadata {
    name      = "aviatrix-mitm-ca"
    namespace = kubernetes_namespace.tls_probe[0].metadata[0].name
  }

  data = {
    "ca.crt" = var.aviatrix_mitm_ca_pem
  }
}

resource "kubernetes_deployment" "tls_probe" {
  count = var.deploy_probes ? 1 : 0
  metadata {
    name      = "tls-probe"
    namespace = kubernetes_namespace.tls_probe[0].metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "tls-probe"
      }
    }

    template {
      metadata {
        labels = {
          app = "tls-probe"
        }
      }

      spec {
        container {
          name    = "probe"
          image   = "curlimages/curl:latest"
          command = ["/bin/sh", "-c"]
          args = [
            "while true; do echo \"$(date -u +%H:%M:%S) $(curl -sf --max-time 5 --cacert /etc/ssl/aviatrix/ca.crt https://ipinfo.io/json || echo BLOCKED)\"; sleep 10; done"
          ]

          volume_mount {
            name       = "aviatrix-ca"
            mount_path = "/etc/ssl/aviatrix"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
          }
        }

        volume {
          name = "aviatrix-ca"
          secret {
            secret_name = kubernetes_secret.aviatrix_ca[0].metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_secret.aviatrix_ca[0]]
}

# ---------------------------------------------------------------------------
# Probe pod in arc-runners namespace (no decryption needed).
# ---------------------------------------------------------------------------

resource "kubernetes_deployment" "ipify_probe" {
  count = var.deploy_probes ? 1 : 0
  metadata {
    name      = "ipify-probe"
    namespace = "arc-runners"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "ipify-probe"
      }
    }

    template {
      metadata {
        labels = {
          app = "ipify-probe"
        }
      }

      spec {
        container {
          name    = "probe"
          image   = "curlimages/curl:latest"
          command = ["/bin/sh", "-c"]
          args = [
            "while true; do echo \"$(date -u +%H:%M:%S) $(curl -sf --max-time 5 https://www.example.com -o /dev/null && echo OK || echo BLOCKED)\"; sleep 10; done"
          ]

          resources {
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.arc_runner_scaleset]
}
