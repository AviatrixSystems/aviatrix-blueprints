# SmartGroup: runner EC2 identified by AWS tag gh-action=runner
resource "aviatrix_smart_group" "runner_vm" {
  name = "${local.name_prefix}-vm"

  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aviatrix_account_name
      tags = {
        "gh-action" = "runner"
      }
    }
  }
}

# WebGroup 1: GitHub Actions runner required FQDNs (TCP 443).
# Driven by var.gh_runner_required_fqdns.
resource "aviatrix_web_group" "gh_runner_required" {
  name = "wg-${local.name_prefix}-required"

  selector {
    dynamic "match_expressions" {
      for_each = var.gh_runner_required_fqdns
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

# WebGroup: Tool-call FQDNs (TCP 80+443). Driven by var.tool_call_fqdns —
# append entries to grow the allow-list without editing this file. Omitted
# entirely when the variable is empty.
resource "aviatrix_web_group" "tool_call" {
  count = length(var.tool_call_fqdns) > 0 ? 1 : 0
  name  = "wg-${local.name_prefix}-tool-call"

  selector {
    dynamic "match_expressions" {
      for_each = var.tool_call_fqdns
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

# WebGroup 2: Ubuntu APT FQDNs for user-data package installation (TCP 80+443).
# Driven by var.linux_pkg_install_fqdns.
resource "aviatrix_web_group" "linux_pkg_install" {
  name = "wg-${local.name_prefix}-linux-pkg"

  selector {
    dynamic "match_expressions" {
      for_each = var.linux_pkg_install_fqdns
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

locals {
  # System SmartGroup: Public Internet destination
  internet_sg_uuid = "def000ad-0000-0000-0000-000000000001"

  # System WebGroup: All-Web (any SNI)
  all_web_wg_uuid = "def000ad-0000-0000-0000-000000000002"

  # System SmartGroup: Aviatrix threat intelligence feed
  default_threat_group_uuid = "def05854-4100-0000-0000-000000000000"
}

# Insert rules directly into the global Distributed Firewalling policy list.
# aviatrix_distributed_firewalling_policy_list manages the controller's
# principal policy list — no ruleset / attachment point needed.
resource "aviatrix_distributed_firewalling_policy_list" "runner" {
  policies {
    name                     = "deny-${local.name_prefix}-threat-group"
    action                   = "DENY"
    priority                 = 10
    protocol                 = "ANY"
    logging                  = true
    exclude_sg_orchestration = true
    src_smart_groups         = [aviatrix_smart_group.runner_vm.uuid]
    dst_smart_groups         = [local.default_threat_group_uuid]
  }

  policies {
    name                     = "allow-${local.name_prefix}-github"
    action                   = "PERMIT"
    priority                 = 20
    protocol                 = "TCP"
    logging                  = true
    exclude_sg_orchestration = true
    src_smart_groups         = [aviatrix_smart_group.runner_vm.uuid]
    dst_smart_groups         = [local.internet_sg_uuid]
    web_groups               = [aviatrix_web_group.gh_runner_required.uuid]

    port_ranges {
      lo = 443
      hi = 443
    }
  }

  dynamic "policies" {
    for_each = length(var.tool_call_fqdns) > 0 ? [1] : []
    content {
      name                     = "allow-${local.name_prefix}-tool-calls"
      action                   = "PERMIT"
      priority                 = 30
      protocol                 = "TCP"
      logging                  = true
      exclude_sg_orchestration = true
      src_smart_groups         = [aviatrix_smart_group.runner_vm.uuid]
      dst_smart_groups         = [local.internet_sg_uuid]
      web_groups               = [aviatrix_web_group.tool_call[0].uuid]

      port_ranges {
        lo = 80
        hi = 80
      }
      port_ranges {
        lo = 443
        hi = 443
      }
    }
  }

  policies {
    name                     = "allow-${local.name_prefix}-linux-setup"
    action                   = "PERMIT"
    priority                 = 40
    protocol                 = "TCP"
    logging                  = true
    exclude_sg_orchestration = true
    src_smart_groups         = [aviatrix_smart_group.runner_vm.uuid]
    dst_smart_groups         = [local.internet_sg_uuid]
    web_groups               = [aviatrix_web_group.linux_pkg_install.uuid]

    port_ranges {
      lo = 80
      hi = 80
    }
    port_ranges {
      lo = 443
      hi = 443
    }
  }

  policies {
    name                     = "deny-${local.name_prefix}-unmatched-web"
    action                   = "DENY"
    watch                    = true # log deny hits without changing enforcement
    priority                 = 50
    protocol                 = "TCP"
    logging                  = true
    exclude_sg_orchestration = true
    src_smart_groups         = [aviatrix_smart_group.runner_vm.uuid]
    dst_smart_groups         = [local.internet_sg_uuid]
    web_groups               = [local.all_web_wg_uuid]

    port_ranges {
      lo = 80
      hi = 80
    }
    port_ranges {
      lo = 443
      hi = 443
    }
  }
}
