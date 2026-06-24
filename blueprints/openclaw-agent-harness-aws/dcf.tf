# =============================================================================
# Aviatrix Distributed Cloud Firewall policy pack
# =============================================================================
# Pattern: SmartGroups identify workload source, WebGroups express allowed or
# explicitly denied FQDNs, and a POST_RULES default action catches unmatched
# egress. This mirrors the Obot MCP blueprint convention while targeting VM-based
# OpenClaw/Hermes/NemoClaw harnesses.
#
# SAFETY NOTE: aviatrix_distributed_firewalling_policy_list and
# aviatrix_distributed_firewalling_default_action_rule are controller-level
# singleton resources. Set manage_controller_policy=false if this controller
# already has a central DCF policy module.
# =============================================================================

# Only manage the controller-global DCF enable flag when this blueprint owns
# controller policy (i.e., a dedicated controller). On a SHARED controller, DCF is
# already enabled by the platform team and must not be toggled here — destroying
# this resource attempts to disable DCF controller-wide (AVXERR-DFW-0008) and would
# affect every other application's policy.
resource "aviatrix_distributed_firewalling_config" "enabled" {
  count                          = var.manage_controller_policy ? 1 : 0
  enable_distributed_firewalling = true
}

resource "time_sleep" "controller_inventory" {
  depends_on      = [module.spoke]
  create_duration = var.controller_sync_wait
}

# Workload-aware source SmartGroup: matches the agent VM by its CSP tag, not a
# static CIDR. The policy follows the workload even if its IP or subnet changes.
# This is the "workload awareness" SmartGroups are designed for. Network-construct
# groups below (DNS resolver, east-west) remain CIDR-based by design.
resource "aviatrix_smart_group" "agent_workload" {
  name = "${local.name}-sg-agent-workload"

  selector {
    match_expressions {
      type = "vm"
      tags = {
        (var.agent_workload_tag_key) = var.agent_workload_tag_value
      }
    }
  }

  depends_on = [time_sleep.controller_inventory]
}

resource "aviatrix_smart_group" "vpc_dns_resolver" {
  name = "${local.name}-sg-vpc-dns-resolver"

  selector {
    match_expressions {
      cidr = local.vpc_dns_resolver_cidr
    }
  }

  depends_on = [time_sleep.controller_inventory]
}

resource "aviatrix_smart_group" "approved_model_gateway_cidrs" {
  count = length(var.approved_model_gateway_cidrs) > 0 ? 1 : 0
  name  = "${local.name}-sg-approved-model-gateway-cidrs"

  selector {
    dynamic "match_expressions" {
      for_each = toset(var.approved_model_gateway_cidrs)
      content {
        cidr = match_expressions.value
      }
    }
  }

  depends_on = [time_sleep.controller_inventory]
}

resource "aviatrix_smart_group" "east_west" {
  name = "${local.name}-sg-east-west-deny"

  selector {
    dynamic "match_expressions" {
      for_each = toset(var.east_west_deny_cidrs)
      content {
        cidr = match_expressions.value
      }
    }
  }

  depends_on = [time_sleep.controller_inventory]
}

resource "aviatrix_web_group" "aws_infra" {
  name = "${local.name}-wg-aws-infra"

  selector {
    dynamic "match_expressions" {
      for_each = toset(local.aws_infra_domains)
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

resource "aviatrix_web_group" "os_updates" {
  count = local.create_os_update_webgroup ? 1 : 0
  name  = "${local.name}-wg-os-updates"

  selector {
    dynamic "match_expressions" {
      for_each = toset(var.os_update_domains)
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

resource "aviatrix_web_group" "openclaw_core" {
  name = "${local.name}-wg-openclaw-core"

  selector {
    dynamic "match_expressions" {
      for_each = toset(var.openclaw_core_domains)
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

resource "aviatrix_web_group" "approved_model_gateways" {
  count = local.create_model_webgroup ? 1 : 0
  name  = "${local.name}-wg-approved-model-gateways"

  selector {
    dynamic "match_expressions" {
      for_each = toset(var.approved_model_gateway_domains)
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

resource "aviatrix_web_group" "package_registries" {
  count = local.create_package_webgroup ? 1 : 0
  name  = "${local.name}-wg-package-registries"

  selector {
    dynamic "match_expressions" {
      for_each = toset(var.package_registry_domains)
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

resource "aviatrix_web_group" "approved_saas_apis" {
  count = local.create_saas_webgroup ? 1 : 0
  name  = "${local.name}-wg-approved-saas-apis"

  selector {
    dynamic "match_expressions" {
      for_each = toset(var.approved_saas_api_domains)
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

resource "aviatrix_web_group" "approved_mcp_gateways" {
  count = local.create_mcp_webgroup ? 1 : 0
  name  = "${local.name}-wg-approved-mcp-gateways"

  selector {
    dynamic "match_expressions" {
      for_each = toset(var.approved_mcp_gateway_domains)
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

resource "aviatrix_web_group" "identity_and_telemetry" {
  count = local.create_identity_webgroup ? 1 : 0
  name  = "${local.name}-wg-identity-telemetry"

  selector {
    dynamic "match_expressions" {
      for_each = toset(var.identity_and_telemetry_domains)
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

resource "aviatrix_web_group" "public_reference" {
  count = local.create_public_ref_webgroup ? 1 : 0
  name  = "${local.name}-wg-public-reference"

  selector {
    dynamic "match_expressions" {
      for_each = toset(var.public_reference_domains)
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

resource "aviatrix_web_group" "unapproved_model_providers" {
  count = local.create_shadow_model_webgroup ? 1 : 0
  name  = "${local.name}-wg-unapproved-model-providers"

  selector {
    dynamic "match_expressions" {
      for_each = toset(var.unapproved_model_provider_domains)
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

resource "aviatrix_distributed_firewalling_policy_list" "openclaw" {
  count = var.manage_controller_policy ? 1 : 0

  depends_on = [
    aviatrix_distributed_firewalling_config.enabled,
    null_resource.policy_guardrails
  ]

  dynamic "policies" {
    for_each = local.create_shadow_model_webgroup ? [1] : []
    content {
      name     = "${local.name}-shadow-model-deny"
      action   = local.deny_like_action
      priority = 10
      protocol = "TCP"
      logging  = true
      watch    = false

      port_ranges {
        lo = 443
        hi = 443
      }

      src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
      dst_smart_groups = [local.aviatrix_anywhere_uuid]
      web_groups       = [aviatrix_web_group.unapproved_model_providers[0].uuid]
    }
  }

  policies {
    name     = "${local.name}-allow-vpc-dns-udp"
    action   = "PERMIT"
    priority = 18
    protocol = "UDP"
    logging  = var.log_permit_rules
    watch    = false

    port_ranges {
      lo = 53
      hi = 53
    }

    src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
    dst_smart_groups = [aviatrix_smart_group.vpc_dns_resolver.uuid]
  }

  policies {
    name     = "${local.name}-allow-vpc-dns-tcp"
    action   = "PERMIT"
    priority = 19
    protocol = "TCP"
    logging  = var.log_permit_rules
    watch    = false

    port_ranges {
      lo = 53
      hi = 53
    }

    src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
    dst_smart_groups = [aviatrix_smart_group.vpc_dns_resolver.uuid]
  }

  policies {
    name     = "${local.name}-deny-dns-exfil-udp"
    action   = local.deny_like_action
    priority = 20
    protocol = "UDP"
    logging  = true
    watch    = false

    port_ranges {
      lo = 53
      hi = 53
    }

    src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
    dst_smart_groups = [local.aviatrix_anywhere_uuid]
  }

  policies {
    name     = "${local.name}-deny-dns-exfil-tcp"
    action   = local.deny_like_action
    priority = 21
    protocol = "TCP"
    logging  = true
    watch    = false

    port_ranges {
      lo = 53
      hi = 53
    }

    src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
    dst_smart_groups = [local.aviatrix_anywhere_uuid]
  }

  policies {
    name     = "${local.name}-allow-aws-infra"
    action   = "PERMIT"
    priority = 30
    protocol = "TCP"
    logging  = var.log_permit_rules
    watch    = false

    port_ranges {
      lo = 443
      hi = 443
    }

    src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
    dst_smart_groups = [local.aviatrix_anywhere_uuid]
    web_groups       = [aviatrix_web_group.aws_infra.uuid]
  }

  dynamic "policies" {
    for_each = local.create_os_update_webgroup ? [1] : []
    content {
      name     = "${local.name}-allow-os-updates-https"
      action   = "PERMIT"
      priority = 31
      protocol = "TCP"
      logging  = var.log_permit_rules
      watch    = false

      port_ranges {
        lo = 443
        hi = 443
      }

      src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
      dst_smart_groups = [local.aviatrix_anywhere_uuid]
      web_groups       = [aviatrix_web_group.os_updates[0].uuid]
    }
  }

  dynamic "policies" {
    for_each = local.create_model_webgroup ? [1] : []
    content {
      name     = "${local.name}-allow-model-gateways"
      action   = "PERMIT"
      priority = 40
      protocol = "TCP"
      logging  = var.log_permit_rules
      watch    = false

      port_ranges {
        lo = 443
        hi = 443
      }

      src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
      dst_smart_groups = [local.aviatrix_anywhere_uuid]
      web_groups       = [aviatrix_web_group.approved_model_gateways[0].uuid]
    }
  }

  dynamic "policies" {
    for_each = length(var.approved_model_gateway_cidrs) > 0 ? [1] : []
    content {
      name     = "${local.name}-allow-model-gateway-cidrs"
      action   = "PERMIT"
      priority = 41
      protocol = "TCP"
      logging  = var.log_permit_rules
      watch    = false

      port_ranges {
        lo = 443
        hi = 443
      }

      src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
      dst_smart_groups = [aviatrix_smart_group.approved_model_gateway_cidrs[0].uuid]
    }
  }

  policies {
    name     = "${local.name}-allow-core"
    action   = "PERMIT"
    priority = 50
    protocol = "TCP"
    logging  = var.log_permit_rules
    watch    = false

    port_ranges {
      lo = 443
      hi = 443
    }

    src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
    dst_smart_groups = [local.aviatrix_anywhere_uuid]
    web_groups       = [aviatrix_web_group.openclaw_core.uuid]
  }

  dynamic "policies" {
    for_each = local.create_package_webgroup ? [1] : []
    content {
      name     = "${local.name}-allow-packages"
      action   = "PERMIT"
      priority = 60
      protocol = "TCP"
      logging  = var.log_permit_rules
      watch    = false

      port_ranges {
        lo = 443
        hi = 443
      }

      src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
      dst_smart_groups = [local.aviatrix_anywhere_uuid]
      web_groups       = [aviatrix_web_group.package_registries[0].uuid]
    }
  }

  dynamic "policies" {
    for_each = local.create_saas_webgroup ? [1] : []
    content {
      name     = "${local.name}-allow-saas-apis"
      action   = "PERMIT"
      priority = 70
      protocol = "TCP"
      logging  = var.log_permit_rules
      watch    = false

      port_ranges {
        lo = 443
        hi = 443
      }

      src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
      dst_smart_groups = [local.aviatrix_anywhere_uuid]
      web_groups       = [aviatrix_web_group.approved_saas_apis[0].uuid]
    }
  }

  dynamic "policies" {
    for_each = local.create_mcp_webgroup ? [1] : []
    content {
      name     = "${local.name}-allow-mcp-gateways"
      action   = "PERMIT"
      priority = 80
      protocol = "TCP"
      logging  = var.log_permit_rules
      watch    = false

      port_ranges {
        lo = 443
        hi = 443
      }

      src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
      dst_smart_groups = [local.aviatrix_anywhere_uuid]
      web_groups       = [aviatrix_web_group.approved_mcp_gateways[0].uuid]
    }
  }

  dynamic "policies" {
    for_each = local.create_identity_webgroup ? [1] : []
    content {
      name     = "${local.name}-allow-identity-telemetry"
      action   = "PERMIT"
      priority = 90
      protocol = "TCP"
      logging  = var.log_permit_rules
      watch    = false

      port_ranges {
        lo = 443
        hi = 443
      }

      src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
      dst_smart_groups = [local.aviatrix_anywhere_uuid]
      web_groups       = [aviatrix_web_group.identity_and_telemetry[0].uuid]
    }
  }

  dynamic "policies" {
    for_each = local.create_public_ref_webgroup ? [1] : []
    content {
      name     = "${local.name}-allow-public-reference"
      action   = "PERMIT"
      priority = 95
      protocol = "TCP"
      logging  = var.log_permit_rules
      watch    = false

      port_ranges {
        lo = 443
        hi = 443
      }

      src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
      dst_smart_groups = [local.aviatrix_anywhere_uuid]
      web_groups       = [aviatrix_web_group.public_reference[0].uuid]
    }
  }

  policies {
    name     = "${local.name}-deny-eastwest"
    action   = local.deny_like_action
    priority = 100
    protocol = "ANY"
    logging  = true
    watch    = false

    src_smart_groups = [aviatrix_smart_group.agent_workload.uuid]
    dst_smart_groups = [aviatrix_smart_group.east_west.uuid]
  }
}

resource "aviatrix_distributed_firewalling_default_action_rule" "deny_all" {
  count   = var.manage_controller_policy ? 1 : 0
  action  = local.default_deny_action
  logging = true

  depends_on = [aviatrix_distributed_firewalling_policy_list.openclaw]
}

resource "null_resource" "copilot_association" {
  count = var.copilot_private_ip == "" ? 0 : 1

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
  count = var.copilot_private_ip == "" ? 0 : 1

  index    = var.copilot_syslog_index
  name     = "${local.name}-copilot"
  server   = var.copilot_private_ip
  port     = 5000
  protocol = "UDP"
}
