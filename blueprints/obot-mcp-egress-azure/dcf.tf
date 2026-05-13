# =============================================================================
# Distributed Cloud Firewall (DCF) Configuration
# =============================================================================

# Onboard the AKS cluster into the Aviatrix controller.
# This enables the controller to discover pod identities and resolve
# Kubernetes workload labels inside SmartGroup selectors.
resource "aviatrix_kubernetes_cluster" "aks" {
  cluster_id          = lower(azurerm_kubernetes_cluster.obot.id)
  use_csp_credentials = true
}

# Allow the controller's Cloud Asset Inventory (CAI) to sync Kubernetes
# workload metadata before creating SmartGroups that use k8s selectors.
resource "time_sleep" "cai_sync" {
  create_duration = "30s"

  depends_on = [
    aviatrix_spoke_gateway.obot,
    aviatrix_kubernetes_cluster.aks,
  ]
}

# Enable Distributed Cloud Firewalling globally on the controller.
resource "aviatrix_distributed_firewalling_config" "enabled" {
  enable_distributed_firewalling = true
}

# Enable the five feature flags required for Kubernetes CRD enforcement.
# These flags reset on controller reboot — the null_resource ensures they
# are re-applied on every `terraform apply`. Without k8s_discovery and
# log_enrichment, CoPilot cannot resolve pod IPs to Kubernetes workloads,
# causing SmartGroup label-based matching to silently fail.
resource "null_resource" "k8s_dcf_features" {
  triggers = {
    controller_ip = var.controller_ip
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -euo pipefail
      CID=$(curl -sk "https://$${CONTROLLER}/v2/api" \
        -d "action=login&username=$${USERNAME}&password=$${PASSWORD}" \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('CID',''))")
      if [ -z "$${CID}" ]; then echo "ERROR: controller login failed" >&2; exit 1; fi
      for feature in k8s k8s_dcf_policies dcf_multi_policies k8s_discovery log_enrichment; do
        curl -sk "https://$${CONTROLLER}/v2/api" \
          --data-urlencode "action=enable_controller_feature" \
          --data-urlencode "CID=$${CID}" \
          --data-urlencode "feature=$${feature}" > /dev/null &
      done
      wait
      echo "All 5 DCF feature flags enabled"
    EOT
    interpreter = ["/bin/bash", "-c"]
    environment = {
      CONTROLLER = var.controller_ip
      USERNAME   = var.controller_username
      PASSWORD   = var.controller_password
    }
  }

  depends_on = [aviatrix_distributed_firewalling_config.enabled]
}

# SmartGroup: all pods in the Obot MCP namespace.
# This is the source selector for the default deny-all rule.
# Obot deploys MCP server pods into var.obot_mcp_namespace.
resource "aviatrix_smart_group" "mcp_servers" {
  name = "${var.name_prefix}-mcp-servers"

  selector {
    match_expressions {
      type          = "k8s"
      k8s_namespace = var.obot_mcp_namespace
    }
  }

  depends_on = [time_sleep.cai_sync]
}

# SmartGroup: all IPs in the AKS node subnet.
# Used as the source for the V1 infrastructure permit rules.
# Azure IP masquerade is disabled (see obot.tf) so pod IPs are preserved
# all the way to the spoke gateway — but the AKS subnet CIDR is still
# needed for the V1 block which evaluates before Kubernetes label matching.
resource "aviatrix_smart_group" "aks_subnet" {
  name = "${var.name_prefix}-aks-subnet"

  selector {
    match_expressions {
      cidr = azurerm_subnet.aks_nodes.address_prefixes[0]
    }
  }

  depends_on = [time_sleep.cai_sync]
}

# SmartGroup: K8s API server public IP (single /32).
# Pods access the Kubernetes API via the ClusterIP (e.g. 172.16.0.1:443),
# which kube-proxy DNATs to this public IP. TLS over an IP has no SNI field
# in the ClientHello, so WebGroup-based matching cannot match this traffic.
# A plain CIDR permit at priority 1 is required.
resource "aviatrix_smart_group" "k8s_api_server" {
  name = "${var.name_prefix}-k8s-api"

  selector {
    match_expressions {
      cidr = "${data.dns_a_record_set.aks_api_server.addrs[0]}/32"
    }
  }

  depends_on = [time_sleep.cai_sync]
}

# SmartGroup: obot-system pods via /32 CIDRs (workaround for V1 CIDR-only source).
# Scopes Obot application domains (Anthropic, GitHub) to orchestration pods only.
# On first apply, var.obot_system_pod_cidrs is empty — the SmartGroup is created
# but matches nothing until re-applied with pod IPs after Obot is running.
resource "aviatrix_smart_group" "obot_system_pods" {
  name = "${var.name_prefix}-obot-system"

  selector {
    dynamic "match_expressions" {
      for_each = var.obot_system_pod_cidrs
      content {
        cidr = match_expressions.value
      }
    }
  }

  depends_on = [time_sleep.cai_sync]
}

# WebGroup: AKS node + pod infrastructure domains (source = full AKS subnet CIDR).
# Azure services and container registries required by all nodes and pods.
resource "aviatrix_web_group" "aks_infra_egress" {
  name = "${var.name_prefix}-aks-infra"

  selector {
    match_expressions { snifilter = "*.hcp.${local.azure_region_slug}.azmk8s.io" }
    match_expressions { snifilter = "*.azurecr.io" }
    match_expressions { snifilter = "*.blob.core.windows.net" }
    match_expressions { snifilter = "*.servicebus.windows.net" }
    match_expressions { snifilter = "mcr.microsoft.com" }
    match_expressions { snifilter = "*.data.mcr.microsoft.com" }
    match_expressions { snifilter = "management.azure.com" }
    match_expressions { snifilter = "login.microsoftonline.com" }
    match_expressions { snifilter = "packages.microsoft.com" }
    match_expressions { snifilter = "acs-mirror.azureedge.net" }
    match_expressions { snifilter = "ghcr.io" }
    match_expressions { snifilter = "*.ghcr.io" }
    match_expressions { snifilter = "pkg-containers.githubusercontent.com" }
    match_expressions { snifilter = "charts.obot.ai" } # NPC chart pulled by Obot PostStart hook
  }
}

# WebGroup: Obot application domains (source = obot-system pod /32 CIDRs only).
resource "aviatrix_web_group" "obot_pod_egress" {
  name = "${var.name_prefix}-obot-egress"

  selector {
    match_expressions { snifilter = "charts.obot.ai" }
    match_expressions { snifilter = "api.anthropic.com" }
    match_expressions { snifilter = "github.com" }
    match_expressions { snifilter = "*.github.com" }
    match_expressions { snifilter = "raw.githubusercontent.com" }
    match_expressions { snifilter = "*.githubusercontent.com" }
  }
}

# V1 policy list: infrastructure permits that must evaluate BEFORE the
# Kubernetes CRD block (K8S_POLICY_LIST) and the default deny rule.
#
# Traffic evaluation order:
#   V1 (this resource) -> K8S_POLICY_LIST (MCPNetworkPolicy CRDs) -> POST_RULES (deny-all)
#
# Do NOT place the deny-all in the V1 list — a V1 deny evaluates before the
# K8S block and would block all MCPNetworkPolicy PERMIT rules.
resource "aviatrix_distributed_firewalling_policy_list" "infra" {
  # P1: K8s API server CIDR permit.
  # Must be priority 1, evaluated before WebGroup rules. Pod→ClusterIP→kube-proxy
  # DNAT→API server IP; no SNI in the ClientHello means WebGroup matching skips.
  policies {
    name     = "k8s-api-server-cidr"
    action   = "PERMIT"
    priority = 1
    protocol = "TCP"
    logging  = true
    watch    = false
    port_ranges {
      lo = 443
      hi = 443
    }
    src_smart_groups = [aviatrix_smart_group.aks_subnet.uuid]
    dst_smart_groups = [aviatrix_smart_group.k8s_api_server.uuid]
  }

  # P2: AKS infrastructure domain egress (SNI-based WebGroup).
  policies {
    name     = "aks-infra-egress"
    action   = "PERMIT"
    priority = 2
    protocol = "TCP"
    logging  = true
    watch    = false
    port_ranges {
      lo = 443
      hi = 443
    }
    src_smart_groups = [aviatrix_smart_group.aks_subnet.uuid]
    dst_smart_groups = ["def000ad-0000-0000-0000-000000000001"] # Aviatrix anywhere group (0.0.0.0/0)
    web_groups       = [aviatrix_web_group.aks_infra_egress.uuid]
  }

  # P3: Obot pod egress — scoped to obot-system pod /32 CIDRs.
  # Provides Anthropic/GitHub/charts.obot.ai access to the orchestration layer
  # without leaking those permits to obot-mcp pods.
  policies {
    name     = "obot-pod-egress"
    action   = "PERMIT"
    priority = 3
    protocol = "TCP"
    logging  = true
    watch    = false
    port_ranges {
      lo = 443
      hi = 443
    }
    src_smart_groups = [aviatrix_smart_group.obot_system_pods.uuid]
    dst_smart_groups = ["def000ad-0000-0000-0000-000000000001"]
    web_groups       = [aviatrix_web_group.obot_pod_egress.uuid]
  }

  depends_on = [aviatrix_distributed_firewalling_config.enabled]
}

# Default deny-all at POST_RULES level.
# Evaluates AFTER V1 and K8S_POLICY_LIST blocks. Any traffic not explicitly
# permitted by a V1 rule or a MCPNetworkPolicy CRD is dropped and logged.
resource "aviatrix_distributed_firewalling_default_action_rule" "deny_all" {
  action  = "DENY"
  logging = true

  depends_on = [aviatrix_distributed_firewalling_policy_list.infra]
}

# CoPilot association via direct API call.
# The aviatrix_copilot_association Terraform resource (provider v8.x) only
# accepts a private IP. Without the public IP, spoke gateway OTEL exporters
# (TCP 31284) silently fail when the spoke VNet is not peered to the
# controlplane VNet: FlowIQ keeps working but DCF Monitor stays empty.
resource "null_resource" "copilot_association" {
  triggers = {
    private_ip = var.copilot_private_ip
    public_ip  = var.copilot_public_ip
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -euo pipefail
      CID=$(curl -sk "https://$${CONTROLLER}/v2/api" \
        -d "action=login&username=$${USERNAME}&password=$${PASSWORD}" \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('CID',''))")
      if [ -z "$${CID}" ]; then echo "ERROR: controller login failed" >&2; exit 1; fi
      curl -sk "https://$${CONTROLLER}/v2/api" \
        -d "action=enable_copilot_association&CID=$${CID}&copilot_ip=$${PRIVATE_IP}&public_ip=$${PUBLIC_IP}"
    EOT
    interpreter = ["/bin/bash", "-c"]
    environment = {
      CONTROLLER = var.controller_ip
      USERNAME   = var.controller_username
      PASSWORD   = var.controller_password
      PRIVATE_IP = var.copilot_private_ip
      PUBLIC_IP  = var.copilot_public_ip
    }
  }
}

resource "aviatrix_remote_syslog" "copilot" {
  index    = var.copilot_syslog_index
  name     = "${var.name_prefix}-copilot"
  server   = var.copilot_private_ip
  port     = 5000
  protocol = "UDP"
}
