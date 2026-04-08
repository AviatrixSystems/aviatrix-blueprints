#####################
# LibreChat - AI Chat Frontend
#
# Open-source ChatGPT-like UI connected to LiteLLM as the AI backend.
# Exposed via ALB Ingress (public).
#####################

#####################
# Secrets (generated per-deployment)
#####################

resource "random_password" "creds_key" {
  length  = 64
  special = false
}

resource "random_password" "creds_iv" {
  length  = 32
  special = false
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "random_password" "jwt_refresh_secret" {
  length  = 64
  special = false
}

resource "kubernetes_secret_v1" "librechat" {
  metadata {
    name      = "librechat-secrets"
    namespace = "default"
  }

  data = {
    CREDS_KEY          = random_password.creds_key.result
    CREDS_IV           = random_password.creds_iv.result
    JWT_SECRET         = random_password.jwt_secret.result
    JWT_REFRESH_SECRET = random_password.jwt_refresh_secret.result
  }
}

resource "kubernetes_config_map_v1" "librechat" {
  metadata {
    name      = "librechat-config"
    namespace = "default"
  }

  data = {
    "librechat.yaml" = yamlencode({
      version = "1.0"
      cache   = true
      endpoints = {
        custom = [
          {
            name    = "Bedrock (via LiteLLM)"
            apiKey  = "sk-placeholder"
            baseURL = "http://litellm.default.svc.cluster.local:4000/v1"
            models = {
              default = ["claude-sonnet", "claude-haiku"]
            }
            titleConvo   = true
            titleModel   = "claude-haiku"
            summarize    = true
            summaryModel = "claude-haiku"
          }
        ]
      }
    })
  }
}

resource "kubernetes_deployment_v1" "librechat" {
  metadata {
    name      = "librechat"
    namespace = "default"
    labels = {
      app = "librechat"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "librechat"
      }
    }

    template {
      metadata {
        labels = {
          app = "librechat"
        }
      }

      spec {
        container {
          name  = "librechat"
          image = "ghcr.io/danny-avila/librechat:v0.8.4"

          port {
            container_port = 3080
          }

          env {
            name  = "MONGO_URI"
            value = "mongodb://mongodb.default.svc.cluster.local:27017/librechat"
          }

          env {
            name  = "HOST"
            value = "0.0.0.0"
          }

          env {
            name  = "PORT"
            value = "3080"
          }

          env {
            name = "CREDS_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.librechat.metadata[0].name
                key  = "CREDS_KEY"
              }
            }
          }

          env {
            name = "CREDS_IV"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.librechat.metadata[0].name
                key  = "CREDS_IV"
              }
            }
          }

          env {
            name = "JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.librechat.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }

          env {
            name = "JWT_REFRESH_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.librechat.metadata[0].name
                key  = "JWT_REFRESH_SECRET"
              }
            }
          }

          env {
            name  = "ALLOW_REGISTRATION"
            value = "true"
          }

          env {
            name  = "ALLOW_SOCIAL_LOGIN"
            value = "false"
          }

          volume_mount {
            name       = "config"
            mount_path = "/app/librechat.yaml"
            sub_path   = "librechat.yaml"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              memory = "1Gi"
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.librechat.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.mongodb,
    kubernetes_deployment_v1.litellm
  ]
}

resource "kubernetes_service_v1" "librechat" {
  metadata {
    name      = "librechat"
    namespace = "default"
  }

  spec {
    selector = {
      app = "librechat"
    }

    port {
      port        = 80
      target_port = 3080
    }
  }
}

#####################
# ALB Ingress (Public)
#####################

resource "kubernetes_ingress_v1" "librechat" {
  metadata {
    name      = "librechat"
    namespace = "default"
    annotations = {
      "kubernetes.io/ingress.class"                = "alb"
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\": 80}]"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/api/health"
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.librechat.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}
