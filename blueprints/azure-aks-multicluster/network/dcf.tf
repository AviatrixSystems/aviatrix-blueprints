#####################
# Aviatrix Distributed Cloud Firewall (DCF)
#
# Architecture:
#   - VNet SmartGroups  : match traffic by VNet name (post-SNAT, transit-level)
#   - Hostname SGs      : match destination services by FQDN
#   - WebGroups         : SNI/URL filters for HTTPS egress inspection
#   - Rules (priority-ordered):
#       0–9   : Threat prevention (geo-block, ThreatIQ)
#       10–29 : East-west (inter-VNet service access)
#       20    : Azure required services (AKS nodes/pods)
#       30–49 : Explicit egress allows
#       50–99 : Reserved for K8s CRD policies (FirewallPolicy / WebGroupPolicy)
#
# NOTES:
#   - DCF inspects traffic at the Aviatrix spoke gateway BEFORE SNAT.
#     Pod source IPs (100.64.x.x) are visible to DCF rules. Aviatrix K8s
#     SmartGroups dynamically resolve pod IPs from cluster label selectors.
#   - For transit-level rules (east-west between spokes), traffic arrives
#     post-SNAT (spoke GW IP). Use VNet-type SmartGroups for those.
#   - Hostname SmartGroups resolve FQDNs via the Azure Private DNS zone.
#####################

#####################
# SmartGroups — VNet-based (transit-level)
#####################

resource "aviatrix_smart_group" "frontend_vnet" {
  name = "${var.name_prefix}-sg-frontend-vnet"
  selector {
    match_expressions {
      type = "vpc"
      name = "${var.name_prefix}-frontend-vnet"
    }
  }
}

resource "aviatrix_smart_group" "backend_vnet" {
  name = "${var.name_prefix}-sg-backend-vnet"
  selector {
    match_expressions {
      type = "vpc"
      name = "${var.name_prefix}-backend-vnet"
    }
  }
}

resource "aviatrix_smart_group" "db_vnet" {
  name = "${var.name_prefix}-sg-db-vnet"
  selector {
    match_expressions {
      type = "vpc"
      name = "${var.name_prefix}-db-vnet"
    }
  }
}

resource "aviatrix_smart_group" "all_aks_clusters" {
  name = "${var.name_prefix}-sg-all-aks"
  selector {
    match_expressions {
      type = "vpc"
      name = "${var.name_prefix}-frontend-vnet"
    }
    match_expressions {
      type = "vpc"
      name = "${var.name_prefix}-backend-vnet"
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
      fqdn = "backend.${var.private_dns_zone_name}"
    }
  }
}

resource "aviatrix_smart_group" "frontend_service" {
  name = "${var.name_prefix}-sg-frontend-service"
  selector {
    match_expressions {
      fqdn = "frontend.${var.private_dns_zone_name}"
    }
  }
}

resource "aviatrix_smart_group" "database" {
  name = "${var.name_prefix}-sg-database"
  selector {
    match_expressions {
      fqdn = "db.${var.private_dns_zone_name}"
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
      ext_args = {
        country_iso_code = "IR" # Iran
      }
    }
    match_expressions {
      external = "geo"
      ext_args = {
        country_iso_code = "KP" # North Korea
      }
    }
    match_expressions {
      external = "geo"
      ext_args = {
        country_iso_code = "RU" # Russia
      }
    }
  }
}

resource "aviatrix_smart_group" "threat_intel" {
  name = "${var.name_prefix}-sg-threat-intel"
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
  # Built-in "Public Internet" SmartGroup UUID (system-defined, matches all non-RFC1918)
  public_internet_uuid = "def000ad-0000-0000-0000-000000000001"
}

#####################
# WebGroups — SNI/URL filters for HTTPS egress
#####################

# Azure services required by AKS nodes and Cilium
resource "aviatrix_web_group" "azure_required" {
  name = "${var.name_prefix}-wg-azure-required"
  selector {
    match_expressions {
      snifilter = "*.microsoft.com"
    }
    match_expressions {
      snifilter = "*.microsoftonline.com"
    }
    match_expressions {
      snifilter = "*.azurecr.io" # Azure Container Registry
    }
    match_expressions {
      snifilter = "mcr.microsoft.com" # Microsoft Container Registry
    }
    match_expressions {
      snifilter = "*.blob.core.windows.net" # Azure Blob (image layers)
    }
    match_expressions {
      snifilter = "*.azure.com"
    }
    match_expressions {
      snifilter = "*.azure.net"
    }
    # AKS-specific endpoints
    match_expressions {
      snifilter = "*.azmk8s.io" # AKS API server
    }
    match_expressions {
      snifilter = "management.azure.com"
    }
    # Ubuntu/Debian package repos (for node bootstrapping)
    match_expressions {
      snifilter = "packages.microsoft.com"
    }
    match_expressions {
      snifilter = "security.ubuntu.com"
    }
    match_expressions {
      snifilter = "archive.ubuntu.com"
    }
  }
}

resource "aviatrix_web_group" "kubernetes_io" {
  name = "${var.name_prefix}-wg-kubernetes-io"
  selector {
    match_expressions {
      snifilter = "kubernetes.io"
    }
    match_expressions {
      snifilter = "*.kubernetes.io"
    }
    match_expressions {
      snifilter = "registry.k8s.io"
    }
    match_expressions {
      snifilter = "*.pkg.dev" # Artifact Registry (k8s images)
    }
  }
}

resource "aviatrix_web_group" "docker_hub" {
  name = "${var.name_prefix}-wg-docker-hub"
  selector {
    match_expressions {
      snifilter = "registry-1.docker.io"
    }
    match_expressions {
      snifilter = "auth.docker.io"
    }
    match_expressions {
      snifilter = "index.docker.io"
    }
    match_expressions {
      snifilter = "*.docker.com"
    }
  }
}

resource "aviatrix_web_group" "npm_registry" {
  name = "${var.name_prefix}-wg-npm-registry"
  selector {
    match_expressions {
      snifilter = "registry.npmjs.org"
    }
    match_expressions {
      snifilter = "npmjs.org"
    }
    match_expressions {
      snifilter = "www.npmjs.com"
    }
  }
}

resource "aviatrix_web_group" "github_aviatrix" {
  name = "${var.name_prefix}-wg-github-aviatrix"
  selector {
    # A WebGroup can only contain one filter type (snifilter OR urlfilter, not both)
    match_expressions {
      snifilter = "github.com"
    }
    match_expressions {
      snifilter = "*.github.com"
    }
    match_expressions {
      snifilter = "*.githubusercontent.com"
    }
    match_expressions {
      snifilter = "aviatrixsystems.github.io"
    }
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

resource "aviatrix_dcf_ruleset" "aks_demo" {
  name      = "${var.name_prefix}-aks-multicluster"
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
    src_smart_groups = [aviatrix_smart_group.all_aks_clusters.uuid]
    dst_smart_groups = [aviatrix_smart_group.geo_blocked.uuid]
  }

  rules {
    name             = "Block Threat Intel IPs"
    action           = "DENY"
    priority         = 1
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.all_aks_clusters.uuid]
    dst_smart_groups = [aviatrix_smart_group.threat_intel.uuid]
  }

  #############################
  # INTER-VNET EAST-WEST (Priority 10-29)
  #############################

  rules {
    name             = "Frontend to Database"
    action           = "PERMIT"
    priority         = 10
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.frontend_vnet.uuid]
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
    src_smart_groups = [aviatrix_smart_group.backend_vnet.uuid]
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
    src_smart_groups = [aviatrix_smart_group.frontend_vnet.uuid]
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
    src_smart_groups = [aviatrix_smart_group.backend_vnet.uuid]
    dst_smart_groups = [aviatrix_smart_group.frontend_service.uuid]
    port_ranges {
      lo = 8080
    }
  }

  #############################
  # EGRESS — Azure Required (Priority 20)
  #############################

  rules {
    name                 = "AKS Required Azure Services"
    action               = "PERMIT"
    priority             = 20
    protocol             = "TCP"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.all_aks_clusters.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.azure_required.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  # AKS nodes also need port 80 for some package managers and HTTP redirects
  rules {
    name                 = "AKS Required Azure Services HTTP"
    action               = "PERMIT"
    priority             = 21
    protocol             = "TCP"
    logging              = false
    src_smart_groups     = [aviatrix_smart_group.all_aks_clusters.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.azure_required.uuid]
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
    src_smart_groups     = [aviatrix_smart_group.all_aks_clusters.uuid]
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
    src_smart_groups     = [aviatrix_smart_group.all_aks_clusters.uuid]
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
    src_smart_groups     = [aviatrix_smart_group.all_aks_clusters.uuid]
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
    src_smart_groups     = [aviatrix_smart_group.all_aks_clusters.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.github_aviatrix.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  #############################
  # K8s-TYPED DEMO (Priority 50)
  # Demonstrates that, once clusters are onboarded, DCF can target K8s
  # namespaces directly. Membership of these SmartGroups (defined in
  # dcf-k8s.tf) is resolved by the controller from the cluster API.
  # Empty until enable_aviatrix_onboarding completes in clusters/*.
  #
  # Gated by var.enable_k8s_smartgroup_demo so the rule + the SmartGroups
  # it references can be removed in a single apply before destroying the
  # clusters layer (the cluster registration cannot be deleted while a
  # SmartGroup references its cluster_id).
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

  #############################
  # PLACEHOLDER: K8s CRD POLICIES (Priority 51-99)
  # Inserted programmatically by Aviatrix k8s-firewall controller.
  # See k8s-apps/dcf-crd/ for FirewallPolicy / WebGroupPolicy CRD examples.
  #############################

  depends_on = [
    aviatrix_distributed_firewalling_config.enable,
    module.frontend_spoke,
    module.backend_spoke,
    module.db_spoke,
  ]
}

#####################
# Outputs
#####################

output "dcf_ruleset_uuid" {
  description = "UUID of the DCF ruleset"
  value       = aviatrix_dcf_ruleset.aks_demo.id
}

output "smartgroup_frontend_vnet_uuid" {
  description = "UUID of frontend VNet SmartGroup"
  value       = aviatrix_smart_group.frontend_vnet.uuid
}

output "smartgroup_backend_vnet_uuid" {
  description = "UUID of backend VNet SmartGroup"
  value       = aviatrix_smart_group.backend_vnet.uuid
}

output "webgroup_azure_required_uuid" {
  description = "UUID of Azure Required WebGroup (for CRD reference)"
  value       = aviatrix_web_group.azure_required.uuid
}

output "webgroup_github_aviatrix_uuid" {
  description = "UUID of GitHub Aviatrix WebGroup (for CRD reference)"
  value       = aviatrix_web_group.github_aviatrix.uuid
}
