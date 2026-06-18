#####################
# Pattern B: Namespace-as-a-Service — Azure DCF (Distributed Cloud Firewall)
#
# SmartGroups are keyed on K8s namespace (type="k8s").
# k8s_cluster_id is REQUIRED alongside k8s_namespace in SmartGroups.
#
# Platform team sets baseline via Terraform; app teams extend via CRDs + GitOps.
# CRD-managed policies fill priority 70-99 (team self-service).
#
# RBAC is NOT a hard security boundary — DCF is the primary network isolation.
#####################

#####################
# Enable Distributed Cloud Firewall
#####################

resource "aviatrix_distributed_firewalling_config" "main" {
  count                          = var.manage_dcf ? 1 : 0
  enable_distributed_firewalling = true
}

# Enable DCF Enforcement on Kubernetes
resource "aviatrix_k8s_config" "main" {
  depends_on          = [aviatrix_distributed_firewalling_config.main]
  enable_k8s          = true
  enable_dcf_policies = true
}

# DCF enablement is async — controller needs time to activate
resource "time_sleep" "wait_for_dcf" {
  count           = var.manage_dcf ? 1 : 0
  depends_on      = [aviatrix_distributed_firewalling_config.main]
  create_duration = "15s"
}

#####################
# SmartGroups: K8s Namespace-type
#
# These SmartGroups match pods by their Kubernetes namespace.
# k8s_cluster_id is required to scope the match to a specific cluster,
# preventing cross-cluster namespace collisions.
#####################

resource "aviatrix_smart_group" "team_a_ns" {
  name = "${local.name_prefix}-team-a-ns"
  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = local.k8s_cluster_name
      k8s_namespace  = "team-a"
    }
  }
}

resource "aviatrix_smart_group" "team_b_ns" {
  name = "${local.name_prefix}-team-b-ns"
  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = local.k8s_cluster_name
      k8s_namespace  = "team-b"
    }
  }
}

resource "aviatrix_smart_group" "team_c_ns" {
  name = "${local.name_prefix}-team-c-ns"
  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = local.k8s_cluster_name
      k8s_namespace  = "team-c"
    }
  }
}

resource "aviatrix_smart_group" "monitoring_ns" {
  name = "${local.name_prefix}-monitoring-ns"
  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = local.k8s_cluster_name
      k8s_namespace  = "monitoring"
    }
  }
}

resource "aviatrix_smart_group" "all_namespaces" {
  name = "${local.name_prefix}-all-team-namespaces"
  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = local.k8s_cluster_name
      k8s_namespace  = "team-a"
    }
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = local.k8s_cluster_name
      k8s_namespace  = "team-b"
    }
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = local.k8s_cluster_name
      k8s_namespace  = "team-c"
    }
  }
}

# VNet SmartGroup for the shared cluster (Azure uses -vnet suffix)
resource "aviatrix_smart_group" "shared_cluster_vnet" {
  name = "${local.name_prefix}-sg-shared-cluster-vnet"
  selector {
    match_expressions {
      type = "vpc"
      name = "${local.name_prefix}-shared-vnet"
    }
  }
}

#####################
# SmartGroups: Geo-block & Threat Intel
#####################

resource "aviatrix_smart_group" "geo_blocked" {
  name = "${local.name_prefix}-sg-geo-blocked"
  selector {
    dynamic "match_expressions" {
      for_each = var.geo_block_countries
      content {
        external = "geo"
        ext_args = {
          country_iso_code = match_expressions.value
        }
      }
    }
  }
}

resource "aviatrix_smart_group" "threat_intel" {
  name = "${local.name_prefix}-sg-threat-intel"
  selector {
    match_expressions {
      external = "threatiq"
      ext_args = {
        severity = "major"
      }
    }
    match_expressions {
      external = "threatiq"
      ext_args = {
        severity = "critical"
      }
    }
  }
}

#####################
# Built-in SmartGroups
#####################

locals {
  public_internet_uuid = "def000ad-0000-0000-0000-000000000001"
}

#####################
# WebGroups
#####################

resource "aviatrix_web_group" "aks_required" {
  name = "${local.name_prefix}-wg-aks-required"
  selector {
    # Microsoft Container Registry (MCR)
    match_expressions {
      snifilter = "mcr.microsoft.com"
    }
    match_expressions {
      snifilter = "*.data.mcr.microsoft.com"
    }
    # Azure Resource Manager (ARM) APIs
    match_expressions {
      snifilter = "management.azure.com"
    }
    # Azure Active Directory / Entra ID
    match_expressions {
      snifilter = "login.microsoftonline.com"
    }
    match_expressions {
      snifilter = "login.microsoft.com"
    }
    match_expressions {
      snifilter = "sts.windows.net"
    }
    # Azure Monitor and Telemetry
    match_expressions {
      snifilter = "dc.services.visualstudio.com"
    }
    match_expressions {
      snifilter = "*.ods.opinsights.azure.com"
    }
    match_expressions {
      snifilter = "*.oms.opinsights.azure.com"
    }
    match_expressions {
      snifilter = "*.monitoring.azure.com"
    }
    # Azure Blob Storage
    match_expressions {
      snifilter = "*.blob.core.windows.net"
    }
    # AKS API Server
    match_expressions {
      snifilter = "*.hcp.*.azmk8s.io"
    }
    match_expressions {
      snifilter = "*.tun.*.azmk8s.io"
    }
    # Ubuntu/Azure Linux Package Repos
    match_expressions {
      snifilter = "packages.microsoft.com"
    }
    match_expressions {
      snifilter = "security.ubuntu.com"
    }
    match_expressions {
      snifilter = "azure.archive.ubuntu.com"
    }
    # Kubernetes Registry
    match_expressions {
      snifilter = "registry.k8s.io"
    }
    match_expressions {
      snifilter = "*.pkg.dev"
    }
  }
}

resource "aviatrix_web_group" "approved_egress" {
  name = "${local.name_prefix}-wg-approved-egress"
  selector {
    dynamic "match_expressions" {
      for_each = var.approved_web_domains
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

#####################
# DCF Ruleset
#
# Priority layout:
#   0-1:   Threat prevention (geo-block, ThreatIQ)
#   5:     Monitoring scrape (monitoring-ns -> all teams)
#   10:    Approved cross-namespace (team-a -> team-b)
#   50-55: Namespace isolation (deny non-communicating pairs)
#   60:    Egress via WebGroups (AKS required + approved domains)
#   70-99: Reserved for CRD-managed rules (team self-service)
#####################

data "aviatrix_dcf_attachment_point" "tf_before_ui" {
  name = "TERRAFORM_BEFORE_UI_MANAGED"
}

resource "aviatrix_dcf_ruleset" "namespace_isolation" {
  depends_on = [time_sleep.wait_for_dcf]
  name       = "${local.name_prefix}-namespace-isolation"
  attach_to  = "defa11a1-3000-4001-0000-000000000000"

  #############################
  # THREAT PREVENTION (Priority 0-1)
  #############################

  rules {
    name             = "Geo-block inbound"
    action           = "DENY"
    priority         = 0
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.geo_blocked.uuid]
    dst_smart_groups = [aviatrix_smart_group.all_namespaces.uuid]
  }

  rules {
    name             = "Block Threat Intel IPs"
    action           = "DENY"
    priority         = 1
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.threat_intel.uuid]
    dst_smart_groups = [aviatrix_smart_group.all_namespaces.uuid]
  }

  #############################
  # MONITORING (Priority 5)
  #############################

  rules {
    name             = "Monitoring scrape all namespaces"
    action           = "PERMIT"
    priority         = 5
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.monitoring_ns.uuid]
    dst_smart_groups = [aviatrix_smart_group.all_namespaces.uuid]
    port_ranges {
      lo = 9090
    }
    port_ranges {
      lo = 9091
    }
  }

  #############################
  # APPROVED CROSS-NAMESPACE (Priority 10)
  #############################

  rules {
    name             = "team-a to team-b API"
    action           = "PERMIT"
    priority         = 10
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_a_ns.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_b_ns.uuid]
    port_ranges {
      lo = 443
    }
  }

  #############################
  # NAMESPACE ISOLATION (Priority 50-55)
  #############################

  rules {
    name             = "DENY team-a to team-c"
    action           = "DENY"
    priority         = 50
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_a_ns.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_c_ns.uuid]
  }

  rules {
    name             = "DENY team-c to team-a"
    action           = "DENY"
    priority         = 51
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_c_ns.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_a_ns.uuid]
  }

  rules {
    name             = "DENY team-b to team-c"
    action           = "DENY"
    priority         = 52
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_b_ns.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_c_ns.uuid]
  }

  rules {
    name             = "DENY team-c to team-b"
    action           = "DENY"
    priority         = 55
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_c_ns.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_b_ns.uuid]
  }

  #############################
  # EGRESS (Priority 60)
  #############################

  rules {
    name                 = "All namespaces egress AKS required"
    action               = "PERMIT"
    priority             = 60
    protocol             = "TCP"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.all_namespaces.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.aks_required.uuid, aviatrix_web_group.approved_egress.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  #############################
  # PRIORITY 70-99: RESERVED FOR CRD-MANAGED RULES
  #
  # These priorities are managed by the k8s-firewall controller via
  # FirewallPolicy and WebGroupPolicy CRDs deployed per-namespace.
  # Platform team does NOT define rules here — app teams own them via GitOps.
  #############################
}
