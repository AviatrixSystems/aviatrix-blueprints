#####################
# Aviatrix Distributed Cloud Firewall (DCF)
#
# Architecture:
#   - VPC SmartGroups   : match traffic by VPC name (post-SNAT, transit-level)
#   - Hostname SGs      : match destination services by FQDN
#   - WebGroups         : SNI/URL filters for HTTPS egress inspection
#   - Rules (priority-ordered):
#       0–9   : Threat prevention (geo-block, ThreatIQ)
#       10–29 : East-west (inter-VPC service access)
#       20–21 : GCP required services (GKE nodes/pods)
#       30–49 : Explicit egress allows
#       50–99 : Reserved for K8s CRD policies (FirewallPolicy / WebGroupPolicy)
#
# NOTES:
#   - DCF inspects traffic at the Aviatrix spoke gateway BEFORE pod-to-spoke
#     SNAT only when the policy's src is a K8s SmartGroup (the GW resolves pod
#     IPs from the cluster API). VPC-typed SmartGroups match post-SNAT, so they
#     see the spoke GW IP as the source for east-west between spokes.
#   - Hostname SmartGroups resolve FQDNs via the Cloud DNS private zone (the
#     spoke GW uses the GCP metadata resolver 169.254.169.254).
#####################

#####################
# SmartGroups — VPC-based (transit-level)
#####################

resource "aviatrix_smart_group" "frontend_vpc" {
  name = "${var.name_prefix}-sg-frontend-vpc"
  selector {
    match_expressions {
      type = "vpc"
      name = module.frontend_vpc.vpc_name
    }
  }
}

resource "aviatrix_smart_group" "backend_vpc" {
  name = "${var.name_prefix}-sg-backend-vpc"
  selector {
    match_expressions {
      type = "vpc"
      name = module.backend_vpc.vpc_name
    }
  }
}

resource "aviatrix_smart_group" "db_vpc" {
  name = "${var.name_prefix}-sg-db-vpc"
  selector {
    match_expressions {
      type = "vpc"
      name = google_compute_network.db.name
    }
  }
}

resource "aviatrix_smart_group" "all_gke_clusters" {
  name = "${var.name_prefix}-sg-all-gke"
  selector {
    match_expressions {
      type = "vpc"
      name = module.frontend_vpc.vpc_name
    }
    match_expressions {
      type = "vpc"
      name = module.backend_vpc.vpc_name
    }
  }
}

#####################
# SmartGroups — Hostname-based (service FQDNs)
#####################

resource "aviatrix_smart_group" "backend_service" {
  name = "${var.name_prefix}-sg-backend-service"
  selector {
    match_expressions {
      fqdn = "backend.${trimsuffix(var.private_dns_zone_name, ".")}"
    }
  }
}

resource "aviatrix_smart_group" "frontend_service" {
  name = "${var.name_prefix}-sg-frontend-service"
  selector {
    match_expressions {
      fqdn = "frontend.${trimsuffix(var.private_dns_zone_name, ".")}"
    }
  }
}

resource "aviatrix_smart_group" "database" {
  name = "${var.name_prefix}-sg-database"
  selector {
    match_expressions {
      fqdn = "db.${trimsuffix(var.private_dns_zone_name, ".")}"
    }
  }
}

#####################
# SmartGroups — External feeds (threat intelligence)
#####################

resource "aviatrix_smart_group" "geo_blocked" {
  name = "${var.name_prefix}-sg-geo-blocked"
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
  name = "${var.name_prefix}-sg-threat-intel"
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
  # Built-in "Public Internet" SmartGroup UUID (system-defined, matches all non-RFC1918)
  public_internet_uuid = "def000ad-0000-0000-0000-000000000001"
}

#####################
# WebGroups — SNI/URL filters for HTTPS egress
#
# GCP/GKE nodes need to reach a different set of cloud-control endpoints than
# AWS/Azure: googleapis.com (most APIs), gcr.io / pkg.dev (container images),
# packages.cloud.google.com (gke-node-image apt), accounts.google.com (auth).
#####################

resource "aviatrix_web_group" "gcp_required" {
  name = "${var.name_prefix}-wg-gcp-required"
  selector {
    match_expressions { snifilter = "*.googleapis.com" } # most GCP APIs
    match_expressions { snifilter = "*.googleusercontent.com" }
    match_expressions { snifilter = "accounts.google.com" } # OAuth
    match_expressions { snifilter = "oauth2.googleapis.com" }
    match_expressions { snifilter = "metadata.google.internal" } # via private path; redundant but harmless

    # Container Registry / Artifact Registry
    match_expressions { snifilter = "gcr.io" }
    match_expressions { snifilter = "*.gcr.io" }
    match_expressions { snifilter = "*.pkg.dev" }

    # GKE node-image apt repos
    match_expressions { snifilter = "packages.cloud.google.com" }
    match_expressions { snifilter = "storage.googleapis.com" } # used by COS/Ubuntu node images

    # OS package repos for node bootstrap
    match_expressions { snifilter = "security.ubuntu.com" }
    match_expressions { snifilter = "archive.ubuntu.com" }
  }
}

resource "aviatrix_web_group" "kubernetes_io" {
  name = "${var.name_prefix}-wg-kubernetes-io"
  selector {
    match_expressions { snifilter = "kubernetes.io" }
    match_expressions { snifilter = "*.kubernetes.io" }
    match_expressions { snifilter = "registry.k8s.io" }
    match_expressions { snifilter = "*.k8s.io" }
  }
}

resource "aviatrix_web_group" "docker_hub" {
  name = "${var.name_prefix}-wg-docker-hub"
  selector {
    match_expressions { snifilter = "registry-1.docker.io" }
    match_expressions { snifilter = "auth.docker.io" }
    match_expressions { snifilter = "index.docker.io" }
    match_expressions { snifilter = "*.docker.com" }
  }
}

resource "aviatrix_web_group" "npm_registry" {
  name = "${var.name_prefix}-wg-npm-registry"
  selector {
    match_expressions { snifilter = "registry.npmjs.org" }
    match_expressions { snifilter = "npmjs.org" }
    match_expressions { snifilter = "www.npmjs.com" }
  }
}

resource "aviatrix_web_group" "github_aviatrix" {
  name = "${var.name_prefix}-wg-github-aviatrix"
  selector {
    match_expressions { snifilter = "github.com" }
    match_expressions { snifilter = "*.github.com" }
    match_expressions { snifilter = "*.githubusercontent.com" }
    match_expressions { snifilter = "aviatrixsystems.github.io" }
  }
}

#####################
# Enable Distributed Cloud Firewall
#####################

resource "aviatrix_distributed_firewalling_config" "enable" {
  enable_distributed_firewalling = true
}

#####################
# DCF Ruleset
#####################

resource "aviatrix_dcf_ruleset" "gke_demo" {
  name      = "${var.name_prefix}-gke-multicluster"
  attach_to = "defa11a1-3000-4001-0000-000000000000"

  #############################
  # THREAT PREVENTION (Priority 0-9)
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
  # INTER-VPC EAST-WEST (Priority 10-29)
  #############################

  rules {
    name             = "Frontend to Database"
    action           = "PERMIT"
    priority         = 10
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.frontend_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.database.uuid]
    port_ranges {
      lo = 80
    }
  }

  rules {
    name             = "Backend to Database"
    action           = "PERMIT"
    priority         = 11
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.backend_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.database.uuid]
    port_ranges {
      lo = 80
    }
  }

  rules {
    name             = "Frontend to Backend Services"
    action           = "PERMIT"
    priority         = 14
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.frontend_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.backend_service.uuid]
    port_ranges {
      lo = 8080
    }
  }

  rules {
    name             = "Backend to Frontend Services"
    action           = "PERMIT"
    priority         = 15
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.backend_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.frontend_service.uuid]
    port_ranges {
      lo = 8080
    }
  }

  #############################
  # EGRESS — GCP Required (Priority 20-21)
  #############################

  rules {
    name                 = "GKE Required GCP Services"
    action               = "PERMIT"
    priority             = 20
    protocol             = "TCP"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.all_gke_clusters.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.gcp_required.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  rules {
    name                 = "GKE Required GCP Services HTTP"
    action               = "PERMIT"
    priority             = 21
    protocol             = "TCP"
    logging              = false
    src_smart_groups     = [aviatrix_smart_group.all_gke_clusters.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.gcp_required.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 80
    }
  }

  #############################
  # EGRESS — Allowed Destinations (Priority 30-49)
  #############################

  rules {
    name                 = "Allow Kubernetes-io"
    action               = "PERMIT"
    priority             = 30
    protocol             = "TCP"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.all_gke_clusters.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.kubernetes_io.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  rules {
    name                 = "Allow Docker Hub"
    action               = "PERMIT"
    priority             = 31
    protocol             = "TCP"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.all_gke_clusters.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.docker_hub.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  rules {
    name                 = "Allow npm Registry"
    action               = "PERMIT"
    priority             = 32
    protocol             = "TCP"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.all_gke_clusters.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.npm_registry.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  rules {
    name                 = "Allow GitHub Aviatrix Repos"
    action               = "PERMIT"
    priority             = 33
    protocol             = "TCP"
    logging              = true
    watch                = true
    src_smart_groups     = [aviatrix_smart_group.all_gke_clusters.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.github_aviatrix.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  #############################
  # K8s-TYPED DEMO (Priority 50)
  # See dcf-k8s.tf — gated by var.enable_k8s_smartgroup_demo so the rule + the
  # SmartGroups it references can be removed in a single apply before
  # destroying the clusters layer.
  #############################

  dynamic "rules" {
    for_each = var.enable_k8s_smartgroup_demo ? [1] : []
    content {
      name             = "Frontend Gatus to Backend Gatus k8s ns selector"
      action           = "PERMIT"
      priority         = 50
      protocol         = "TCP"
      logging          = true
      src_smart_groups = [aviatrix_smart_group.frontend_gatus_ns[0].uuid]
      dst_smart_groups = [aviatrix_smart_group.backend_gatus_ns[0].uuid]
      port_ranges {
        lo = 8080
      }
    }
  }

  # Sequence priority-50 rule removal before the SmartGroup destroy when
  # enable_k8s_smartgroup_demo flips true → false. Without this, the dynamic
  # rules block disappears from the plan graph and the controller rejects the
  # SG destroy with [AVXERR-SMARTGROUP-0003].
  depends_on = [
    aviatrix_distributed_firewalling_config.enable,
    module.frontend_spoke,
    module.backend_spoke,
    module.db_spoke,
    aviatrix_smart_group.frontend_gatus_ns,
    aviatrix_smart_group.backend_gatus_ns,
    aviatrix_smart_group.frontend_cluster,
    aviatrix_smart_group.backend_cluster,
  ]
}
