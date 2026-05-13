# =============================================================================
# Obot Platform Deployment
# =============================================================================
#
# Obot uses embedded SQLite by default (dev.useEmbeddedDb: true).
# For production, replace with an external PostgreSQL database by setting
# OBOT_SERVER_DSN in the config block and setting dev.useEmbeddedDb: false.
# =============================================================================

resource "helm_release" "obot" {
  name             = "obot"
  repository       = "https://charts.obot.ai"
  chart            = "obot"
  version          = var.obot_version
  namespace        = var.obot_namespace
  create_namespace = false # created in k8s.tf

  values = [
    yamlencode({
      image = {
        repository = "ghcr.io/obot-platform/obot"
        tag        = "v${var.obot_version}"
        pullPolicy = "IfNotPresent"
      }
      # Embedded SQLite — suitable for evaluation and single-node deployments.
      # Replace with external PostgreSQL for production (set OBOT_SERVER_DSN).
      dev = {
        useEmbeddedDb = true
      }
      updateStrategy = "Recreate"
      service = {
        type = "ClusterIP"
        port = 80
      }
      ingress = {
        enabled = false
      }
      mcpNamespace = {
        name = var.obot_mcp_namespace
        networkPolicy = {
          enabled = false
        }
        podSecurity = {
          enabled = false
        }
      }
      config = {
        OBOT_SERVER_ENABLE_AUTHENTICATION                    = false
        OBOT_SERVER_ENABLE_REGISTRY_AUTH                     = false
        OBOT_SERVER_MCPRUNTIME_BACKEND                       = "kubernetes"
        OBOT_SERVER_MCPBASE_IMAGE                            = "ghcr.io/obot-platform/obot"
        OBOT_SERVER_NANOBOT_INTEGRATION                      = true
        OBOT_SERVER_DISABLE_LEGACY_CHAT                      = true
        NAH_THREADINESS                                      = "10000"
        OBOT_SERVER_ADMIN_PASSWORD                           = var.obot_admin_password
        OBOT_SERVER_MCPNETWORK_POLICY_PROVIDER_CHART_REPO    = "https://charts.obot.ai"
        OBOT_SERVER_MCPNETWORK_POLICY_PROVIDER_CHART_NAME    = "aviatrix-network-policy-controller"
        OBOT_SERVER_MCPNETWORK_POLICY_PROVIDER_CHART_VERSION = var.npc_chart_version
        OBOT_SERVER_MCPDEFAULT_DENY_ALL_EGRESS               = "true"
      }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.obot_system,
    kubernetes_namespace_v1.obot_mcp,
    null_resource.k8s_dcf_features,
    module.spoke,
    aviatrix_distributed_firewalling_policy_list.infra,
    aviatrix_distributed_firewalling_default_action_rule.deny_all,
  ]
}
