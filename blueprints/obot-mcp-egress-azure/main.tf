# =============================================================================
# Blueprint: obot-mcp-egress-azure
# Deploys an AKS cluster with Aviatrix spoke gateway and Obot, enforcing
# zero-trust egress on all MCP server pods via DCF + MCPNetworkPolicy.
# =============================================================================

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

provider "azurerm" {
  subscription_id = var.azure_subscription_id
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "aviatrix" {
  controller_ip           = var.controller_ip
  username                = var.controller_username
  password                = var.controller_password
  skip_version_validation = true
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.obot.kube_config[0].host
  username               = azurerm_kubernetes_cluster.obot.kube_config[0].username
  password               = azurerm_kubernetes_cluster.obot.kube_config[0].password
  client_certificate     = base64decode(azurerm_kubernetes_cluster.obot.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.obot.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.obot.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.obot.kube_config[0].host
    username               = azurerm_kubernetes_cluster.obot.kube_config[0].username
    password               = azurerm_kubernetes_cluster.obot.kube_config[0].password
    client_certificate     = base64decode(azurerm_kubernetes_cluster.obot.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.obot.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.obot.kube_config[0].cluster_ca_certificate)
  }
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  # Azure region slug used in AKS API server domain (e.g. "UK South" -> "uksouth")
  azure_region_slug = lower(replace(var.azure_location, " ", ""))

  # Placeholder CIDR (RFC 5737 TEST-NET-1) used when obot_system_pod_cidrs is
  # empty on first apply. The Aviatrix provider requires at least one
  # match_expressions block in a SmartGroup selector. This placeholder creates a
  # valid but non-matching group; it is replaced on second apply once real pod
  # IPs are supplied.
  obot_system_pod_cidrs_effective = length(var.obot_system_pod_cidrs) > 0 ? var.obot_system_pod_cidrs : ["192.0.2.0/32"]
}

# -----------------------------------------------------------------------------
# AKS API server IP (derived from cluster FQDN after creation)
# Pods reach the K8s API via a ClusterIP that kube-proxy DNATs to this public
# IP. TLS over a bare IP has no SNI field, so WebGroup matching cannot apply.
# A CIDR-based permit at priority 1 (dcf.tf) is required.
# -----------------------------------------------------------------------------

data "dns_a_record_set" "aks_api_server" {
  host = azurerm_kubernetes_cluster.obot.fqdn
}
