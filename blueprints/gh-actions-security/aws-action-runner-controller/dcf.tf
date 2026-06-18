locals {
  # Aviatrix system SmartGroups / WebGroups — well-known UUIDs.
  internet_sg_uuid          = "def000ad-0000-0000-0000-000000000001"
  all_web_wg_uuid           = "def000ad-0000-0000-0000-000000000002"
  default_threat_group_uuid = "def05854-4100-0000-0000-000000000000"
  # Built-in DCF log profile: session-start only.
  log_profile_start_uuid = "def000ad-7000-0000-0000-000000000001"
}

# SmartGroup — ARC runner pods (arc-runners namespace).
resource "aviatrix_smart_group" "runner_pods" {
  name = "${local.name_prefix}-runner-pods"

  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = lower(module.eks.cluster_arn)
      k8s_namespace  = "arc-runners"
    }
  }

  depends_on = [aviatrix_kubernetes_cluster.this]
}

# SmartGroup — TLS-decrypt probe pod (arc-tls-probe namespace).
resource "aviatrix_smart_group" "tls_probe" {
  name = "${local.name_prefix}-tls-probe"

  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = lower(module.eks.cluster_arn)
      k8s_namespace  = "arc-tls-probe"
    }
  }

  depends_on = [aviatrix_kubernetes_cluster.this]
}

# SmartGroup — ARC system pods (arc-systems namespace: controller + listener).
resource "aviatrix_smart_group" "arc_systems" {
  name = "${local.name_prefix}-arc-systems"

  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = lower(module.eks.cluster_arn)
      k8s_namespace  = "arc-systems"
    }
  }

  depends_on = [aviatrix_kubernetes_cluster.this]
}

# TLS profile: SNI verification + strict certificate validation (ENFORCE).
# Applied to every DCF rule that uses a web_group so the GW validates
# origin certificates and SNI on intercepted TLS sessions.
resource "aviatrix_dcf_tls_profile" "strict" {
  display_name           = "${local.name_prefix}-strict"
  verify_sni             = true
  ca_bundle_id           = "def000ad-6000-0000-0000-000000000002"
  certificate_validation = "CERTIFICATE_VALIDATION_ENFORCE"
}

# WebGroup 1: GitHub Actions runner required FQDNs (TCP 443).
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

# WebGroup: TLS-probe target — url-based filter forces GW to decrypt to match HTTP path.
resource "aviatrix_web_group" "tls_probe_target" {
  name = "wg-${local.name_prefix}-tls-probe"

  selector {
    match_expressions {
      urlfilter = "ipinfo.io/json"
    }
  }
}

# WebGroup 2: Tool-call FQDNs (TCP 80+443). Omitted when var.tool_call_fqdns is empty.
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

# WebGroup 3: Container registry + APT FQDNs for EKS node bootstrap and pod
# image pulls (ECR, Docker Hub, Ubuntu APT).
resource "aviatrix_web_group" "linux_pkg_install" {
  name = "wg-${local.name_prefix}-linux-pkg"

  selector {
    dynamic "match_expressions" {
      for_each = [
        "archive.ubuntu.com",
        "security.ubuntu.com",
        "esm.ubuntu.com",
        "api.snapcraft.io",
        "*.amazonaws.com",
        "registry-1.docker.io",
        "auth.docker.io",
        "production.cloudflare.docker.com",
        "ghcr.io",
        "*.ghcr.io",
      ]
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

# Insert rules directly into the global Distributed Firewalling policy list.
resource "aviatrix_distributed_firewalling_policy_list" "runner" {

  policies {
    name                     = "allow-${local.name_prefix}-arc-systems"
    action                   = "PERMIT"
    priority                 = 5
    protocol                 = "TCP"
    logging                  = true
    log_profile              = local.log_profile_start_uuid
    exclude_sg_orchestration = true
    tls_profile              = aviatrix_dcf_tls_profile.strict.uuid
    src_smart_groups         = [aviatrix_smart_group.arc_systems.uuid]
    dst_smart_groups         = [local.internet_sg_uuid]
    web_groups               = [aviatrix_web_group.gh_runner_required.uuid]

    port_ranges {
      lo = 443
      hi = 443
    }
  }

  policies {
    name                     = "deny-${local.name_prefix}-threat-group"
    action                   = "DENY"
    priority                 = 10
    protocol                 = "ANY"
    logging                  = true
    log_profile              = local.log_profile_start_uuid
    exclude_sg_orchestration = true
    src_smart_groups         = [aviatrix_smart_group.runner_pods.uuid]
    dst_smart_groups         = [local.default_threat_group_uuid]
  }

  policies {
    name                     = "allow-${local.name_prefix}-github"
    action                   = "PERMIT"
    priority                 = 20
    protocol                 = "TCP"
    logging                  = true
    log_profile              = local.log_profile_start_uuid
    exclude_sg_orchestration = true
    tls_profile              = aviatrix_dcf_tls_profile.strict.uuid
    src_smart_groups         = [aviatrix_smart_group.runner_pods.uuid]
    dst_smart_groups         = [local.internet_sg_uuid]
    web_groups               = [aviatrix_web_group.gh_runner_required.uuid]

    port_ranges {
      lo = 443
      hi = 443
    }
  }

  policies {
    name                     = "allow-${local.name_prefix}-tls-probe-decrypt"
    action                   = "PERMIT"
    decrypt_policy           = "DECRYPT_ALLOWED"
    flow_app_requirement     = "TLS_REQUIRED"
    tls_profile              = aviatrix_dcf_tls_profile.strict.uuid
    priority                 = 25
    protocol                 = "TCP"
    logging                  = true
    log_profile              = local.log_profile_start_uuid
    exclude_sg_orchestration = true
    src_smart_groups         = [aviatrix_smart_group.tls_probe.uuid]
    dst_smart_groups         = [local.internet_sg_uuid]
    web_groups               = [aviatrix_web_group.tls_probe_target.uuid]

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
      log_profile              = local.log_profile_start_uuid
      exclude_sg_orchestration = true
      tls_profile              = aviatrix_dcf_tls_profile.strict.uuid
      src_smart_groups         = [aviatrix_smart_group.runner_pods.uuid]
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
    log_profile              = local.log_profile_start_uuid
    exclude_sg_orchestration = true
    tls_profile              = aviatrix_dcf_tls_profile.strict.uuid
    src_smart_groups         = [aviatrix_smart_group.runner_pods.uuid]
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
    watch                    = false
    priority                 = 50
    protocol                 = "TCP"
    logging                  = true
    log_profile              = local.log_profile_start_uuid
    exclude_sg_orchestration = true
    tls_profile              = aviatrix_dcf_tls_profile.strict.uuid
    src_smart_groups         = [aviatrix_smart_group.runner_pods.uuid]
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
