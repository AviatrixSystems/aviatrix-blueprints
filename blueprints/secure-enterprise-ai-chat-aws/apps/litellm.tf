#####################
# LiteLLM - AI Gateway Proxy
#
# Routes AI API requests to AWS Bedrock using IRSA for authentication.
# LibreChat connects to LiteLLM as an OpenAI-compatible endpoint.
#####################

resource "kubernetes_config_map_v1" "litellm" {
  metadata {
    name      = "litellm-config"
    namespace = "default"
  }

  data = {
    "config.yaml" = yamlencode({
      model_list = [
        {
          model_name = "claude-sonnet"
          litellm_params = {
            model           = "bedrock/us.anthropic.claude-sonnet-4-6"
            aws_region_name = data.terraform_remote_state.infra.outputs.aws_region
          }
        },
        {
          model_name = "claude-haiku"
          litellm_params = {
            model           = "bedrock/us.anthropic.claude-haiku-4-5-20251001-v1:0"
            aws_region_name = data.terraform_remote_state.infra.outputs.aws_region
          }
        }
      ]
    })
  }
}

resource "kubernetes_service_account_v1" "litellm" {
  metadata {
    name      = "litellm"
    namespace = "default"
    annotations = {
      "eks.amazonaws.com/role-arn" = data.terraform_remote_state.infra.outputs.litellm_bedrock_role_arn
    }
  }
}

resource "kubernetes_deployment_v1" "litellm" {
  metadata {
    name      = "litellm"
    namespace = "default"
    labels = {
      app = "litellm"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "litellm"
      }
    }

    template {
      metadata {
        labels = {
          app = "litellm"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.litellm.metadata[0].name

        container {
          name  = "litellm"
          image = "ghcr.io/berriai/litellm:v1.82.3-stable.patch.2"

          args = ["--config", "/etc/litellm/config.yaml"]

          port {
            container_port = 4000
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/litellm"
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
            name = kubernetes_config_map_v1.litellm.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "litellm" {
  metadata {
    name      = "litellm"
    namespace = "default"
  }

  spec {
    selector = {
      app = "litellm"
    }

    port {
      port        = 4000
      target_port = 4000
    }
  }
}
