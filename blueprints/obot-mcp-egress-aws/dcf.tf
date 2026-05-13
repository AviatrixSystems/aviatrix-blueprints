# =============================================================================
# Distributed Cloud Firewall (DCF) Configuration
# =============================================================================
#
# KNOWN LIMITATION — EKS per-pod K8s label enforcement:
# EKS clusters register as "Partial" (controller cannot list custom resources).
# K8s label-based SmartGroups never resolve pod IPs, so FirewallPolicy CRDs
# created by NPC are not enforced at the spoke gateway.
# Workaround: V1 CIDR /32 SmartGroups (var.obot_system_pod_cidrs,
# var.obot_mcp_pod_cidrs) provide enforcement until Aviatrix resolves the
# EKS kubeconfig exec-plugin or assetd watcher re-subscription issue.
# See docs/stp-eks-dcf-per-pod-enforcement.md for full root cause.
# =============================================================================
#
# SINGLETON RESOURCES: aviatrix_distributed_firewalling_policy_list and
# aviatrix_distributed_firewalling_default_action_rule are controller-level
# singletons. If applying multiple blueprints against the same Aviatrix
# controller, only one blueprint should own these resources; the second apply
# will overwrite the first's policy rules. Merge rules into a shared module or
# use separate controllers per blueprint deployment.

resource "aviatrix_kubernetes_cluster" "obot" {
  cluster_id          = module.eks.cluster_arn
  use_csp_credentials = true
}

resource "time_sleep" "cai_sync" {
  depends_on = [
    module.spoke,
    aviatrix_kubernetes_cluster.obot,
  ]
  create_duration = "30s"
}

resource "aviatrix_distributed_firewalling_config" "enabled" {
  enable_distributed_firewalling = true
}

# Re-enable 5 DCF feature flags (reset on controller reboot).
resource "null_resource" "k8s_dcf_features" {
  triggers = { controller_ip = var.controller_ip }

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

# SmartGroup: obot-mcp namespace (K8s label selector — does not resolve on EKS).
# Retained for when the EKS enforcement gap is fixed upstream.
resource "aviatrix_smart_group" "mcp_servers" {
  name = "${local.name}-mcp-servers"
  selector {
    match_expressions {
      type          = "k8s"
      k8s_namespace = var.obot_mcp_namespace
    }
  }
  depends_on = [time_sleep.cai_sync]
}

# SmartGroup: EKS VPC CIDR (source for infra permit rules)
resource "aviatrix_smart_group" "eks_vpc" {
  name = "${local.name}-eks-vpc"
  selector {
    match_expressions {
      cidr = var.vpc_cidr
    }
  }
  depends_on = [time_sleep.cai_sync]
}

# SmartGroup: obot-system pod /32 CIDRs (V1 CIDR workaround).
# Empty match_expressions on first apply produces a valid SmartGroup that
# matches nothing until re-applied with pod IPs after Obot is running.
resource "aviatrix_smart_group" "obot_system_pods" {
  name = "${local.name}-obot-system"
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

# SmartGroup: obot-mcp pod /32 CIDRs (V1 CIDR workaround for DENY enforcement).
resource "aviatrix_smart_group" "mcp_pod_ips" {
  count = length(var.obot_mcp_pod_cidrs) > 0 ? 1 : 0
  name  = "${local.name}-obot-mcp-pod-ips"
  selector {
    dynamic "match_expressions" {
      for_each = var.obot_mcp_pod_cidrs
      content {
        cidr = match_expressions.value
      }
    }
  }
  depends_on = [time_sleep.cai_sync]
}

# WebGroup: EKS infrastructure egress (ECR, S3, SSM, EC2, EKS endpoints)
resource "aviatrix_web_group" "eks_infra_egress" {
  name = "${local.name}-eks-infra"
  selector {
    match_expressions { snifilter = "*.eks.amazonaws.com" }
    match_expressions { snifilter = "*.ecr.aws" }
    match_expressions { snifilter = "*.dkr.ecr.*.amazonaws.com" }
    match_expressions { snifilter = "*.s3.*.amazonaws.com" }
    match_expressions { snifilter = "*.s3.amazonaws.com" }
    match_expressions { snifilter = "ec2.*.amazonaws.com" }
    match_expressions { snifilter = "ssm.*.amazonaws.com" }
    match_expressions { snifilter = "sts.amazonaws.com" }
    match_expressions { snifilter = "sts.*.amazonaws.com" }
    match_expressions { snifilter = "ghcr.io" }
    match_expressions { snifilter = "*.ghcr.io" }
    match_expressions { snifilter = "pkg-containers.githubusercontent.com" }
    match_expressions { snifilter = "charts.obot.ai" } # NPC chart pulled by Obot PostStart hook
  }
}

# WebGroup: Obot application domains (scoped to obot-system pods only)
resource "aviatrix_web_group" "obot_pod_egress" {
  name = "${local.name}-obot-egress"
  selector {
    match_expressions { snifilter = "charts.obot.ai" }
    match_expressions { snifilter = "api.anthropic.com" }
    match_expressions { snifilter = "github.com" }
    match_expressions { snifilter = "*.github.com" }
    match_expressions { snifilter = "raw.githubusercontent.com" }
    match_expressions { snifilter = "*.githubusercontent.com" }
  }
}

# V1 policy list: EKS infra + obot-system permits evaluated before K8S block.
resource "aviatrix_distributed_firewalling_policy_list" "infra" {
  # P1: EKS infrastructure egress (ECR, S3, SSM, EC2, EKS endpoints)
  policies {
    name     = "eks-infra-egress"
    action   = "PERMIT"
    priority = 1
    protocol = "TCP"
    logging  = true
    watch    = false
    port_ranges { lo = 443 }
    src_smart_groups = [aviatrix_smart_group.eks_vpc.uuid]
    dst_smart_groups = ["def000ad-0000-0000-0000-000000000001"] # Aviatrix anywhere group (0.0.0.0/0)
    web_groups       = [aviatrix_web_group.eks_infra_egress.uuid]
  }

  # P2: Obot pod egress — scoped to obot-system /32 CIDRs.
  # When obot_system_pod_cidrs is empty (first apply), this rule has an
  # empty-selector SmartGroup as source and will not match any traffic.
  policies {
    name     = "obot-pod-egress"
    action   = "PERMIT"
    priority = 2
    protocol = "TCP"
    logging  = true
    watch    = false
    port_ranges { lo = 443 }
    src_smart_groups = [aviatrix_smart_group.obot_system_pods.uuid]
    dst_smart_groups = ["def000ad-0000-0000-0000-000000000001"] # Aviatrix anywhere group (0.0.0.0/0)
    web_groups       = [aviatrix_web_group.obot_pod_egress.uuid]
  }

  # P3: Deny all external egress for obot-mcp pods (when CIDRs provided).
  dynamic "policies" {
    for_each = length(var.obot_mcp_pod_cidrs) > 0 ? [1] : []
    content {
      name             = "eks-obot-mcp-deny-external"
      action           = "DENY"
      priority         = 3
      protocol         = "TCP"
      logging          = true
      watch            = false
      src_smart_groups = [aviatrix_smart_group.mcp_pod_ips[0].uuid]
      dst_smart_groups = ["def000ad-0000-0000-0000-000000000001"] # Aviatrix anywhere group (0.0.0.0/0)
    }
  }

  depends_on = [aviatrix_distributed_firewalling_config.enabled]
}

# Default deny-all at POST_RULES level.
resource "aviatrix_distributed_firewalling_default_action_rule" "deny_all" {
  action     = "DENY"
  logging    = true
  depends_on = [aviatrix_distributed_firewalling_policy_list.infra]
}

# CoPilot association via direct API call (provider resource lacks public_ip field).
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
  name     = "${local.name}-copilot"
  server   = var.copilot_private_ip
  port     = 5000
  protocol = "UDP"
}
