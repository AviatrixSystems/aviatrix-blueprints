#####################
# SmartGroups
#####################

resource "aviatrix_smart_group" "cluster_vpc" {
  name = "sg-${var.name_prefix}-vnet"
  selector {
    match_expressions {
      type = "vpc"
      name = "${var.name_prefix}-vnet"
    }
  }
}

resource "aviatrix_smart_group" "geo_blocked" {
  name = "sg-${var.name_prefix}-geo-blocked"
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
  name = "sg-${var.name_prefix}-threat-intel"
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

locals {
  # Built-in "Public Internet" SmartGroup UUID (matches all non-RFC1918 IPs).
  public_internet_uuid = "def000ad-0000-0000-0000-000000000001"
}

#####################
# WebGroups - Allowed Egress
#####################

resource "aviatrix_web_group" "azure_required" {
  name = "wg-${var.name_prefix}-azure-required"
  selector {
    match_expressions { snifilter = "*.azmk8s.io" }
    match_expressions { snifilter = "*.azurecr.io" }
    match_expressions { snifilter = "mcr.microsoft.com" }
    match_expressions { snifilter = "*.data.mcr.microsoft.com" }
    match_expressions { snifilter = "management.azure.com" }
    match_expressions { snifilter = "login.microsoftonline.com" }
    match_expressions { snifilter = "packages.microsoft.com" }
    match_expressions { snifilter = "*.blob.core.windows.net" }
    match_expressions { snifilter = "*.pkg.dev" }
    match_expressions { snifilter = "registry.k8s.io" }
    match_expressions { snifilter = "archive.ubuntu.com" }
    match_expressions { snifilter = "security.ubuntu.com" }
    match_expressions { snifilter = "acs-mirror.azureedge.net" }
    match_expressions { snifilter = "packages.aks.azure.com" }
  }
}

resource "aviatrix_web_group" "kubernetes_io" {
  name = "wg-${var.name_prefix}-kubernetes-io"
  selector {
    match_expressions { snifilter = "kubernetes.io" }
  }
}

resource "aviatrix_web_group" "npm_registry" {
  name = "wg-${var.name_prefix}-npm-registry"
  selector {
    match_expressions { snifilter = "registry.npmjs.org" }
    match_expressions { snifilter = "npmjs.org" }
    match_expressions { snifilter = "www.npmjs.com" }
  }
}

resource "aviatrix_web_group" "github_aviatrix" {
  name = "wg-${var.name_prefix}-github-aviatrix"
  selector {
    match_expressions { urlfilter = "github.com/AviatrixSystems/terraform-provider-aviatrix" }
    match_expressions { urlfilter = "github.com/AviatrixSystems/avxlabs-docs" }
  }
}

#####################
# Enable Distributed Cloud Firewall (controller-wide)
#
# REQUIRED: without this, the ruleset below is configured but NOT enforced —
# gateways pass all traffic (the allow-list "works" only because nothing is
# blocked, and the geo/threat DENY rules never fire). This is the global DCF
# toggle; the ruleset depends_on it so enablement is sequenced first.
#####################

resource "aviatrix_distributed_firewalling_config" "enable" {
  enable_distributed_firewalling = true
}

#####################
# DCF Ruleset (threat prevention + egress allow-list, no default deny)
#####################

resource "aviatrix_dcf_ruleset" "egress" {
  name = "${var.name_prefix}-egress"
  # Attachment point: TERRAFORM_BEFORE_UI_MANAGED. Hardcoded UUID because the
  # TERRAFORM_BEFORE_UI_MANAGED data source returns an incorrect ID on the controller.
  attach_to = "defa11a1-3000-4001-0000-000000000000"

  depends_on = [aviatrix_distributed_firewalling_config.enable]

  rules {
    name             = "Block GeoBlocked Countries"
    action           = "DENY"
    priority         = 0
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.cluster_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.geo_blocked.uuid]
  }

  rules {
    name             = "Block Threat Intel IPs"
    action           = "DENY"
    priority         = 1
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.cluster_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.threat_intel.uuid]
  }

  rules {
    name                 = "Azure Required Services"
    action               = "PERMIT"
    priority             = 20
    protocol             = "TCP"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.cluster_vpc.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.azure_required.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  rules {
    name                 = "Allow kubernetes-io"
    action               = "PERMIT"
    priority             = 30
    protocol             = "TCP"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.cluster_vpc.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.kubernetes_io.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  rules {
    name                 = "Allow GitHub Aviatrix Repos"
    action               = "PERMIT"
    priority             = 31
    protocol             = "TCP"
    logging              = true
    watch                = true
    src_smart_groups     = [aviatrix_smart_group.cluster_vpc.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.github_aviatrix.uuid]
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
    src_smart_groups     = [aviatrix_smart_group.cluster_vpc.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.npm_registry.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  # Priority 50-99 reserved for k8s-firewall CRD injections (see k8s-apps/dcf-crd/).
  # NO default-deny: dst 0.0.0.0/0 would also match RFC1918 inter-VNet traffic.
}
