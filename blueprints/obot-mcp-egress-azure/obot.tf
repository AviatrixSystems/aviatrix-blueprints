# =============================================================================
# Obot Platform Deployment
# =============================================================================

# Disable Azure IP masquerade for pod traffic.
# Without this, Azure's ip-masq-agent rewrites pod source IPs to node IPs
# before traffic reaches the spoke gateway. SmartGroups resolve to pod IPs,
# so the gateway would see node IPs and FirewallPolicy rules would never match.
# Setting nonMasqueradeCIDRs: 0.0.0.0/0 disables SNAT for all destinations,
# preserving pod IPs end-to-end for Kubernetes label-based DCF enforcement.
resource "kubernetes_config_map_v1" "ip_masq_config" {
  metadata {
    name      = "azure-ip-masq-agent-config"
    namespace = "kube-system"
    labels = {
      component                         = "ip-masq-agent"
      "kubernetes.io/cluster-service"   = "true"
      "addonmanager.kubernetes.io/mode" = "EnsureExists"
    }
  }
  data = {
    "ip-masq-agent" = <<-EOT
      nonMasqueradeCIDRs:
        - "0.0.0.0/0"
    EOT
  }
}

# Obot platform namespace.
resource "kubernetes_namespace_v1" "obot_system" {
  metadata {
    name = var.obot_namespace
    labels = {
      app  = "obot"
      role = "platform"
    }
  }
}

# Obot MCP server namespace.
# Obot deploys MCP server pods into this namespace.
# The DCF SmartGroup (dcf.tf) and MCPNetworkPolicy CRDs target this namespace.
resource "kubernetes_namespace_v1" "obot_mcp" {
  metadata {
    name = var.obot_mcp_namespace
    labels = {
      app  = "obot"
      role = "mcp-servers"
    }
  }
}

# Obot Helm release.
# Chart source: https://charts.obot.ai (published on each release)
# Requires Obot with MCPNetworkPolicy (aviatrix egress provider) support.
#
# Key configuration:
# - updateStrategy: Recreate — Obot uses a RWO PVC; RollingUpdate causes
#   Multi-Attach errors if a new pod starts before the old one releases the volume.
# - OBOT_SERVER_MCPNETWORK_POLICY_PROVIDER_*: tells Obot where to pull the
#   aviatrix-network-policy-controller Helm chart (repo, name, version).
# - OBOT_SERVER_MCPDEFAULT_DENY_ALL_EGRESS: enables deny-all default for new
#   MCP servers. Servers with no MCPNetworkPolicy get zero outbound access.
resource "helm_release" "obot" {
  name             = "obot"
  repository       = "https://charts.obot.ai"
  chart            = "obot"
  version          = var.obot_version
  namespace        = var.obot_namespace
  create_namespace = false

  values = [
    yamlencode({
      updateStrategy = "Recreate"
      dev = {
        useEmbeddedDb = true
      }
      mcpNamespace = {
        name = var.obot_mcp_namespace
      }
      config = {
        OBOT_SERVER_MCPNETWORK_POLICY_PROVIDER_CHART_REPO    = "https://charts.obot.ai"
        OBOT_SERVER_MCPNETWORK_POLICY_PROVIDER_CHART_NAME    = "aviatrix-network-policy-controller"
        OBOT_SERVER_MCPNETWORK_POLICY_PROVIDER_CHART_VERSION = var.npc_chart_version
        OBOT_SERVER_MCPDEFAULT_DENY_ALL_EGRESS               = "true"
        OBOT_SERVER_ADMIN_PASSWORD                           = var.obot_admin_password
      }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.obot_system,
    kubernetes_namespace_v1.obot_mcp,
    kubernetes_config_map_v1.ip_masq_config,
    aviatrix_spoke_gateway.obot,
    null_resource.k8s_dcf_features,
    aviatrix_distributed_firewalling_policy_list.infra,
    aviatrix_distributed_firewalling_default_action_rule.deny_all,
  ]
}
