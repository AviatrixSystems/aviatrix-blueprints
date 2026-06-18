#####################
# Enable Distributed Cloud Firewall
#####################

resource "aviatrix_distributed_firewalling_config" "main" {
  count                          = var.manage_dcf ? 1 : 0
  enable_distributed_firewalling = true
}

resource "aviatrix_k8s_config" "main" {
  depends_on          = [aviatrix_distributed_firewalling_config.main]
  enable_k8s          = true
  enable_dcf_policies = true
}

resource "time_sleep" "wait_for_dcf" {
  count           = var.manage_dcf ? 1 : 0
  depends_on      = [aviatrix_distributed_firewalling_config.main]
  create_duration = "15s"
}


# -----------------------------------------------------------------------------
# Pattern C: Two-Layer Distributed Cloud Firewall — AWS
#
# Layer 1: VPC SmartGroups for environment isolation (prod <-> nonprod blocked)
# Layer 2: K8s Namespace SmartGroups for team isolation within each cluster
#
# CRITICAL:
#   - Both env directions explicitly denied (prod->nonprod AND nonprod->prod)
#   - DB spoke only reachable from prod VPC
#   - k8s_cluster_id different for prod vs nonprod SmartGroups
#   - Sandbox namespace in nonprod has relaxed egress but NO prod data access
# -----------------------------------------------------------------------------

# ===========================================================================
# Layer 1: VPC SmartGroups — Environment Boundary
# ===========================================================================

resource "aviatrix_smart_group" "prod_vpc" {
  name = "${local.name_prefix}-prod-vpc"

  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        "avx:vpc-name" = aviatrix_vpc.prod.name
      }
    }
  }
}

resource "aviatrix_smart_group" "nonprod_vpc" {
  name = "${local.name_prefix}-nonprod-vpc"

  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        "avx:vpc-name" = aviatrix_vpc.nonprod.name
      }
    }
  }
}

resource "aviatrix_smart_group" "prod_db" {
  name = "${local.name_prefix}-prod-db"

  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        "avx:vpc-name" = aviatrix_vpc.db.name
      }
    }
  }
}

# ===========================================================================
# Layer 2: K8s Namespace SmartGroups — Team Boundary
# NOTE: k8s_cluster_id is different for prod vs nonprod clusters
# ===========================================================================

# --- Production cluster namespaces ---

resource "aviatrix_smart_group" "team_a_prod" {
  name = "${local.name_prefix}-team-a-prod"

  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = var.prod_cluster_id
      k8s_namespace  = "team-a-prod"
    }
  }
}

resource "aviatrix_smart_group" "team_b_prod" {
  name = "${local.name_prefix}-team-b-prod"

  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = var.prod_cluster_id
      k8s_namespace  = "team-b-prod"
    }
  }
}

resource "aviatrix_smart_group" "monitoring_prod" {
  name = "${local.name_prefix}-monitoring-prod"

  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = var.prod_cluster_id
      k8s_namespace  = "monitoring"
    }
  }
}

# --- Non-production cluster namespaces ---

resource "aviatrix_smart_group" "team_a_dev" {
  name = "${local.name_prefix}-team-a-dev"

  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = var.nonprod_cluster_id
      k8s_namespace  = "team-a-dev"
    }
  }
}

resource "aviatrix_smart_group" "team_b_staging" {
  name = "${local.name_prefix}-team-b-staging"

  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = var.nonprod_cluster_id
      k8s_namespace  = "team-b-staging"
    }
  }
}

resource "aviatrix_smart_group" "sandbox" {
  name = "${local.name_prefix}-sandbox"

  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = var.nonprod_cluster_id
      k8s_namespace  = "sandbox"
    }
  }
}

resource "aviatrix_smart_group" "monitoring_nonprod" {
  name = "${local.name_prefix}-monitoring-nonprod"

  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = var.nonprod_cluster_id
      k8s_namespace  = "monitoring"
    }
  }
}

# --- Aggregate SmartGroups ---

resource "aviatrix_smart_group" "all_clusters" {
  name = "${local.name_prefix}-all-clusters"

  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        "avx:vpc-name" = aviatrix_vpc.prod.name
      }
    }
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        "avx:vpc-name" = aviatrix_vpc.nonprod.name
      }
    }
  }
}

# ===========================================================================
# SmartGroups — Threat Prevention
# ===========================================================================

resource "aviatrix_smart_group" "geo_blocked" {
  name = "${local.name_prefix}-sg-geo-blocked"
  selector {
    match_expressions {
      external = "geo"
      ext_args = { country_iso_code = "IR" }
    }
    match_expressions {
      external = "geo"
      ext_args = { country_iso_code = "KP" }
    }
    match_expressions {
      external = "geo"
      ext_args = { country_iso_code = "RU" }
    }
  }
}

resource "aviatrix_smart_group" "threat_intel" {
  name = "${local.name_prefix}-sg-threat-intel"
  selector {
    match_expressions {
      external = "threatiq"
      ext_args = { severity = "major" }
    }
    match_expressions {
      external = "threatiq"
      ext_args = { severity = "critical" }
    }
  }
}

# ===========================================================================
# WebGroups — Egress control
# ===========================================================================

resource "aviatrix_web_group" "public_internet" {
  name = "${local.name_prefix}-public-internet"

  selector {
    match_expressions {
      snifilter = "*.amazonaws.com"
    }
    match_expressions {
      snifilter = "*.docker.io"
    }
    match_expressions {
      snifilter = "ghcr.io"
    }
    match_expressions {
      snifilter = "*.github.com"
    }
    match_expressions {
      snifilter = "registry.k8s.io"
    }
  }
}

resource "aviatrix_web_group" "prod_approved_apis" {
  name = "${local.name_prefix}-prod-approved-apis"

  selector {
    match_expressions {
      snifilter = "*.amazonaws.com"
    }
    match_expressions {
      snifilter = "registry.k8s.io"
    }
  }
}

resource "aviatrix_web_group" "sandbox_relaxed_egress" {
  name = "${local.name_prefix}-sandbox-relaxed-egress"

  selector {
    match_expressions {
      snifilter = "*"
    }
  }
}

# ===========================================================================
# DCF Policy Group + Ruleset
# Each blueprint creates its own policy group attached to a built-in point.
# The ruleset is a child of the policy group via ruleset_reference.
# ===========================================================================

data "aviatrix_dcf_attachment_point" "pre_hook" {
  name = "PRE_HOOK"
}

resource "aviatrix_dcf_policy_group" "pattern_c" {
  name      = "${local.name_prefix}-prod-nonprod-hybrid-group"
  attach_to = data.aviatrix_dcf_attachment_point.pre_hook.id

  ruleset_reference {
    priority    = 100
    target_uuid = aviatrix_dcf_ruleset.pattern_c.id
  }
}

resource "aviatrix_dcf_ruleset" "pattern_c" {
  depends_on = [time_sleep.wait_for_dcf]
  name       = "${local.name_prefix}-prod-nonprod-hybrid"

  # ----- Priority 0: Geo-blocking -----
  rules {
    name             = "${local.name_prefix}-geo-block"
    action           = "DENY"
    priority         = 0
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.all_clusters.uuid]
    dst_smart_groups = [aviatrix_smart_group.geo_blocked.uuid]
  }

  # ----- Priority 1: Threat Intelligence -----
  rules {
    name             = "${local.name_prefix}-threatiq-block"
    action           = "DENY"
    priority         = 1
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.all_clusters.uuid]
    dst_smart_groups = [aviatrix_smart_group.threat_intel.uuid]
  }

  # ===================================================================
  # Layer 1: Environment Isolation (VPC SmartGroups)
  # ===================================================================

  rules {
    name             = "${local.name_prefix}-deny-prod-to-nonprod"
    action           = "DENY"
    priority         = 10
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.prod_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.nonprod_vpc.uuid]
  }

  rules {
    name             = "${local.name_prefix}-deny-nonprod-to-prod"
    action           = "DENY"
    priority         = 11
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.nonprod_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.prod_vpc.uuid]
  }

  # ===================================================================
  # Prod Data Protection
  # ===================================================================

  rules {
    name             = "${local.name_prefix}-prod-to-db"
    action           = "PERMIT"
    priority         = 20
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.prod_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.prod_db.uuid]
    port_ranges {
      lo = 3306
    }
    port_ranges {
      lo = 5432
    }
  }

  rules {
    name             = "${local.name_prefix}-deny-nonprod-to-db"
    action           = "DENY"
    priority         = 21
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.nonprod_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.prod_db.uuid]
  }

  # ===================================================================
  # Layer 2: Namespace Isolation (K8s SmartGroups)
  # ===================================================================

  rules {
    name             = "${local.name_prefix}-deny-teama-dev-to-teamb-staging"
    action           = "DENY"
    priority         = 30
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_a_dev.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_b_staging.uuid]
  }

  rules {
    name             = "${local.name_prefix}-deny-teamb-staging-to-teama-dev"
    action           = "DENY"
    priority         = 31
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_b_staging.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_a_dev.uuid]
  }

  rules {
    name             = "${local.name_prefix}-monitoring-scrape"
    action           = "PERMIT"
    priority         = 32
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [
      aviatrix_smart_group.monitoring_prod.uuid,
      aviatrix_smart_group.monitoring_nonprod.uuid,
    ]
    dst_smart_groups = [
      aviatrix_smart_group.team_a_prod.uuid,
      aviatrix_smart_group.team_b_prod.uuid,
      aviatrix_smart_group.team_a_dev.uuid,
      aviatrix_smart_group.team_b_staging.uuid,
      aviatrix_smart_group.sandbox.uuid,
    ]
    port_ranges {
      lo = 9090
      hi = 9091
    }
  }

  # ===================================================================
  # Egress Controls
  # ===================================================================

  rules {
    name             = "${local.name_prefix}-egress-allowed"
    action           = "PERMIT"
    priority         = 50
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.all_clusters.uuid]
    dst_smart_groups = ["def000ad-0000-0000-0000-000000000001"]
    web_groups       = [aviatrix_web_group.public_internet.uuid]
    port_ranges {
      lo = 443
    }
  }

  rules {
    name             = "${local.name_prefix}-sandbox-egress"
    action           = "PERMIT"
    priority         = 51
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.sandbox.uuid]
    dst_smart_groups = ["def000ad-0000-0000-0000-000000000001"]
    web_groups       = [aviatrix_web_group.sandbox_relaxed_egress.uuid]
    port_ranges {
      lo = 443
    }
  }

  # ===================================================================
  # Priority 70-99: Reserved for CRD-managed rules (team self-service)
  # ===================================================================
}
