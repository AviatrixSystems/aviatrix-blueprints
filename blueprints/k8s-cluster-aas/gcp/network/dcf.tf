#####################
# Distributed Cloud Firewall (DCF) Policies - GCP / Pattern A
#
# Pattern A: Cluster-as-a-Service
#   Each team has a dedicated GKE cluster in its own VPC.
#   DCF uses VPC-level SmartGroups for inter-team isolation.
#
# IMPORTANT LESSONS LEARNED:
#   - DCF sees POST-SNAT traffic (spoke gateway IPs), not pod IPs
#   - Use VPC type SmartGroups for source matching (match by VPC name)
#   - Use Hostname SmartGroups for service destinations
#   - Always deny BOTH directions explicitly between isolated teams
#   - Do NOT use 0.0.0.0/0 as default deny destination (blocks RFC1918 too)
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
# SmartGroups - VPC Based (Infrastructure)
#####################

resource "aviatrix_smart_group" "team_a_vpc" {
  name = "${local.name_prefix}-sg-team-a-vpc"
  selector {
    match_expressions {
      type = "vpc"
      name = "${local.name_prefix}-team-a"
    }
  }
}

resource "aviatrix_smart_group" "team_b_vpc" {
  name = "${local.name_prefix}-sg-team-b-vpc"
  selector {
    match_expressions {
      type = "vpc"
      name = "${local.name_prefix}-team-b"
    }
  }
}

resource "aviatrix_smart_group" "team_c_vpc" {
  name = "${local.name_prefix}-sg-team-c-vpc"
  selector {
    match_expressions {
      type = "vpc"
      name = "${local.name_prefix}-team-c"
    }
  }
}

resource "aviatrix_smart_group" "db_vpc" {
  name = "${local.name_prefix}-sg-db-vpc"
  selector {
    match_expressions {
      type = "vpc"
      name = "${local.name_prefix}-db-spoke"
    }
  }
}

resource "aviatrix_smart_group" "all_gke_clusters" {
  name = "${local.name_prefix}-sg-all-gke-clusters"
  selector {
    match_expressions {
      type = "vpc"
      name = "${local.name_prefix}-team-a"
    }
    match_expressions {
      type = "vpc"
      name = "${local.name_prefix}-team-b"
    }
    match_expressions {
      type = "vpc"
      name = "${local.name_prefix}-team-c"
    }
  }
}

#####################
# SmartGroups - Hostname Based (Service Endpoints)
#####################

resource "aviatrix_smart_group" "team_a_service" {
  name = "${local.name_prefix}-sg-team-a-svc"
  selector {
    match_expressions {
      fqdn = "team-a.${var.dns_private_zone_name}"
    }
  }
}

resource "aviatrix_smart_group" "team_b_service" {
  name = "${local.name_prefix}-sg-team-b-svc"
  selector {
    match_expressions {
      fqdn = "team-b.${var.dns_private_zone_name}"
    }
  }
}

resource "aviatrix_smart_group" "team_c_service" {
  name = "${local.name_prefix}-sg-team-c-svc"
  selector {
    match_expressions {
      fqdn = "team-c.${var.dns_private_zone_name}"
    }
  }
}

resource "aviatrix_smart_group" "database" {
  name = "${local.name_prefix}-sg-database"
  selector {
    match_expressions {
      fqdn = "db.${var.dns_private_zone_name}"
    }
  }
}

#####################
# SmartGroups - External Feeds (Threats)
#####################

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

#####################
# Built-in SmartGroups
#####################

locals {
  public_internet_uuid = "def000ad-0000-0000-0000-000000000001"
}

#####################
# WebGroups - GKE Required Services
#####################

resource "aviatrix_web_group" "gke_required" {
  name = "${local.name_prefix}-wg-gke-required"
  selector {
    match_expressions { snifilter = "gcr.io" }
    match_expressions { snifilter = "*.gcr.io" }
    match_expressions { snifilter = "storage.googleapis.com" }
    match_expressions { snifilter = "*.pkg.dev" }
    match_expressions { snifilter = "artifactregistry.googleapis.com" }
    match_expressions { snifilter = "*.googleapis.com" }
    match_expressions { snifilter = "dl.google.com" }
    match_expressions { snifilter = "packages.cloud.google.com" }
    match_expressions { snifilter = "accounts.google.com" }
    match_expressions { snifilter = "oauth2.googleapis.com" }
    match_expressions { snifilter = "dns.googleapis.com" }
    match_expressions { snifilter = "registry.k8s.io" }
    match_expressions { snifilter = "prod-registry-k8s-io-*.s3.dualstack.*.amazonaws.com" }
    match_expressions { snifilter = "metadata.google.internal" }
  }
}

resource "aviatrix_web_group" "kubernetes_io" {
  name = "${local.name_prefix}-wg-kubernetes-io"
  selector {
    match_expressions { snifilter = "kubernetes.io" }
  }
}

resource "aviatrix_web_group" "github_aviatrix" {
  name = "${local.name_prefix}-wg-github-aviatrix"
  selector {
    match_expressions { urlfilter = "github.com/AviatrixSystems/terraform-provider-aviatrix" }
    match_expressions { urlfilter = "github.com/AviatrixSystems/avxlabs-docs" }
  }
}

#####################
# DCF Ruleset
#####################

data "aviatrix_dcf_attachment_point" "tf_before_ui" {
  name = "TERRAFORM_BEFORE_UI_MANAGED"
}

resource "aviatrix_dcf_ruleset" "caas" {
  depends_on = [time_sleep.wait_for_dcf]
  name       = "${local.name_prefix}-caas"
  attach_to  = "defa11a1-3000-4002-0000-000000000000"  # TERRAFORM_AFTER_UI_MANAGED

  #############################
  # THREAT PREVENTION (Priority 0-1)
  #############################

  rules {
    name             = "Block GeoBlocked Countries"
    action           = "DENY"
    priority         = 0
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.all_gke_clusters.uuid]
    dst_smart_groups = [aviatrix_smart_group.geo_blocked.uuid]
  }

  rules {
    name             = "Block Threat Intel IPs"
    action           = "DENY"
    priority         = 1
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.all_gke_clusters.uuid]
    dst_smart_groups = [aviatrix_smart_group.threat_intel.uuid]
  }

  #############################
  # INTER-TEAM EAST-WEST (Priority 10-11)
  #############################

  rules {
    name             = "Team-A to Team-B API - HTTPS"
    action           = "PERMIT"
    priority         = 10
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_a_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_b_service.uuid]
    port_ranges {
      lo = 443
    }
  }

  rules {
    name             = "Team-B to Team-A API - 8080"
    action           = "PERMIT"
    priority         = 11
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_b_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_a_service.uuid]
    port_ranges {
      lo = 8080
    }
  }

  #############################
  # INTER-TEAM DENY (Priority 20-25)
  # CRITICAL: Always deny BOTH directions explicitly
  #############################

  rules {
    name             = "Deny Team-A to Team-C"
    action           = "DENY"
    priority         = 20
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_a_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_c_vpc.uuid]
  }

  rules {
    name             = "Deny Team-C to Team-A"
    action           = "DENY"
    priority         = 21
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_c_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_a_vpc.uuid]
  }

  rules {
    name             = "Deny Team-B to Team-C"
    action           = "DENY"
    priority         = 22
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_b_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_c_vpc.uuid]
  }

  rules {
    name             = "Deny Team-C to Team-B"
    action           = "DENY"
    priority         = 23
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_c_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_b_vpc.uuid]
  }

  #############################
  # EGRESS - GKE Required (Priority 50)
  #############################

  rules {
    name                 = "GKE Required GCP Services"
    action               = "PERMIT"
    priority             = 50
    protocol             = "TCP"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.all_gke_clusters.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.gke_required.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  #############################
  # DEFAULT DENY - INTENTIONALLY OMITTED
  #
  # DO NOT add a default deny rule with dst_smart_groups = public_internet (0.0.0.0/0)
  # because 0.0.0.0/0 matches ALL traffic including private RFC1918 addresses.
  # This would block inter-VPC traffic even with explicit permit rules above.
  #############################
}

#####################
# Outputs
#####################

output "dcf_ruleset_uuid" {
  value = aviatrix_dcf_ruleset.caas.id
}

output "smartgroup_team_a_vpc_uuid" {
  value = aviatrix_smart_group.team_a_vpc.uuid
}

output "smartgroup_team_b_vpc_uuid" {
  value = aviatrix_smart_group.team_b_vpc.uuid
}

output "smartgroup_team_c_vpc_uuid" {
  value = aviatrix_smart_group.team_c_vpc.uuid
}
