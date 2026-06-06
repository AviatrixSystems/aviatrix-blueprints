#####################
# Distributed Cloud Firewall (DCF) Policies
#
# This file defines SmartGroups, WebGroups, and DCF Rulesets for the single-cluster EKS blueprint.
#
# Architecture:
#   - Cluster VPC - single EKS cluster spoke VPC (named after var.name_prefix)
#   - Pod CIDR (100.64.0.0/16) - SNAT'd to spoke gateway IP
#
# Policy Structure:
#   1. Threat Prevention (GeoBlock, ThreatIQ) - Priority 0-9
#   2. Egress with WebGroups (DPI) - Priority 20-49
#
# IMPORTANT LESSONS LEARNED:
#   - DCF sees POST-SNAT traffic (spoke gateway IPs), not pod IPs
#   - Use VPC type SmartGroups for source matching (match by VPC name)
#   - Default deny with dst=0.0.0.0/0 blocks all traffic - DO NOT USE
#
# NOTE: K8s CRD-based policies (FirewallPolicy, WebGroupPolicy) can be applied
# directly in-cluster for namespace-level controls. See k8s-apps/dcf-crd/ for examples.
#####################

#####################
# SmartGroups - VPC Based (Infrastructure)
# Match by VPC name for source traffic identification
#####################

resource "aviatrix_smart_group" "cluster_vpc" {
  name = "sg-${var.name_prefix}-vpc"
  selector {
    match_expressions {
      type = "vpc"
      name = var.name_prefix
    }
  }
}

#####################
# SmartGroups - External Feeds (Threats)
#####################

resource "aviatrix_smart_group" "geo_blocked" {
  name = "sg-geo-blocked"
  selector {
    match_expressions {
      external = "geo"
      ext_args = {
        country_iso_code = "IR"
      }
    }
    match_expressions {
      external = "geo"
      ext_args = {
        country_iso_code = "KP"
      }
    }
    match_expressions {
      external = "geo"
      ext_args = {
        country_iso_code = "RU"
      }
    }
  }
}

resource "aviatrix_smart_group" "threat_intel" {
  name = "sg-threat-intel"
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
# These are system-defined SmartGroups provided by Aviatrix
#####################

locals {
  # Built-in "Public Internet" SmartGroup UUID
  # This is a system-defined SmartGroup that matches all public (non-RFC1918) IPs
  public_internet_uuid = "def000ad-0000-0000-0000-000000000001"
}

#####################
# WebGroups - Allowed Egress (SNI Filter)
#####################

resource "aviatrix_web_group" "kubernetes_io" {
  name = "wg-kubernetes-io"
  selector {
    match_expressions {
      snifilter = "kubernetes.io"
    }
  }
}

resource "aviatrix_web_group" "npm_registry" {
  name = "wg-npm-registry"
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

#####################
# WebGroups - Allowed Egress (URL Path Filter)
# Demonstrates granular URL-based filtering within allowed domain
#####################

resource "aviatrix_web_group" "github_aviatrix" {
  name = "wg-github-aviatrix"
  selector {
    match_expressions {
      urlfilter = "github.com/AviatrixSystems/terraform-provider-aviatrix"
    }
    match_expressions {
      urlfilter = "github.com/AviatrixSystems/avxlabs-docs"
    }
  }
}

#####################
# WebGroups - EKS Required Services (Catch-all)
# These are required for EKS cluster operation
#####################

resource "aviatrix_web_group" "eks_required" {
  name = "wg-eks-required"
  selector {
    ###################################
    # ECR - AWS EKS Managed Account Only
    # 602401143452 is AWS's EKS container account
    ###################################
    match_expressions {
      snifilter = "602401143452.dkr.ecr.*.amazonaws.com"
    }
    match_expressions {
      snifilter = "api.ecr.*.amazonaws.com"
    }

    ###################################
    # ECR - Public Registry (read-only)
    ###################################
    match_expressions {
      snifilter = "public.ecr.aws"
    }
    match_expressions {
      snifilter = "api.ecr-public.*.amazonaws.com"
    }

    ###################################
    # S3 - AWS-Owned EKS/SSM Buckets Only
    # Locked to specific AWS bucket naming patterns
    ###################################
    # AL2023 package repositories
    match_expressions {
      snifilter = "al2023-repos-*.s3.dualstack.*.amazonaws.com"
    }
    # SSM agent/documents
    match_expressions {
      snifilter = "amazon-ssm-*.s3.*.amazonaws.com"
    }
    # SSM patch baselines
    match_expressions {
      snifilter = "patch-baseline-snapshot-*.s3.*.amazonaws.com"
    }
    # Kubernetes registry S3 storage layer
    match_expressions {
      snifilter = "prod-registry-k8s-io-*.s3.dualstack.*.amazonaws.com"
    }
    # EKS container layer storage
    match_expressions {
      snifilter = "prod-*-starport-layer-bucket.s3.*.amazonaws.com"
    }

    ###################################
    # EC2 & Instance Services (APIs only)
    ###################################
    match_expressions {
      snifilter = "ec2.*.amazonaws.com"
    }
    match_expressions {
      snifilter = "ec2messages.*.amazonaws.com"
    }

    ###################################
    # Systems Manager (SSM) APIs
    ###################################
    match_expressions {
      snifilter = "ssm.*.amazonaws.com"
    }
    match_expressions {
      snifilter = "ssmmessages.*.amazonaws.com"
    }

    ###################################
    # Identity & Auth APIs
    ###################################
    match_expressions {
      snifilter = "sts.*.amazonaws.com"
    }
    match_expressions {
      snifilter = "cognito-identity.*.amazonaws.com"
    }

    ###################################
    # DNS (global service)
    ###################################
    match_expressions {
      snifilter = "route53.amazonaws.com"
    }

    ###################################
    # Telemetry (EKS node telemetry)
    ###################################
    match_expressions {
      snifilter = "pinpoint.*.amazonaws.com"
    }

    ###################################
    # EKS API (control plane)
    ###################################
    match_expressions {
      snifilter = "*.eks.amazonaws.com"
    }

    ###################################
    # CloudFront - ECR/EKS CDN only
    # TODO: Lock to specific distribution IDs if known
    ###################################
    match_expressions {
      snifilter = "*.cloudfront.net"
    }

    ###################################
    # Kubernetes Registry
    ###################################
    match_expressions {
      snifilter = "registry.k8s.io"
    }
    match_expressions {
      snifilter = "*.pkg.dev"
    }
  }
}

#####################
# Enable Distributed Cloud Firewall (controller-wide)
#
# REQUIRED: without this, the ruleset below is configured but NOT enforced —
# gateways pass all traffic (the egress allow-list "passes" only because nothing
# is blocked, and the geo/threat DENY rules never fire). This is the global DCF
# toggle; the ruleset depends_on it so enablement is sequenced first.
# (Verified live: a standalone spoke does NOT enforce DCF until this is set.)
#####################

resource "aviatrix_distributed_firewalling_config" "enable" {
  enable_distributed_firewalling = true
}

#####################
# DCF Ruleset
#####################

data "aviatrix_dcf_attachment_point" "tf_before_ui" {
  name = "TERRAFORM_BEFORE_UI_MANAGED"
}

resource "aviatrix_dcf_ruleset" "k8s_demo" {
  name = "${var.name_prefix}-egress"
  # TODO: revert to data source once Controller returns correct ID
  # attach_to = data.aviatrix_dcf_attachment_point.tf_before_ui.id
  attach_to = "defa11a1-3000-4001-0000-000000000000"

  depends_on = [aviatrix_distributed_firewalling_config.enable]

  #############################
  # THREAT PREVENTION (Priority 0-9)
  # Block malicious traffic before any permit rules
  #############################

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

  #############################
  # EGRESS - EKS Required (Priority 20)
  # Allow EKS cluster operational traffic
  #############################

  rules {
    name                 = "EKS Required AWS Services"
    action               = "PERMIT"
    priority             = 20
    protocol             = "TCP"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.cluster_vpc.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.eks_required.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  #############################
  # EGRESS - Allowed Destinations (Priority 30-49)
  # Explicit allow for specific external services
  #############################

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

  #############################
  # PLACEHOLDER FOR K8S CRD POLICIES (Priority 50-99)
  #
  # K8s CRD-based policies (FirewallPolicy, WebGroupPolicy) are applied
  # directly in the cluster and will be inserted at these priority levels.
  # See k8s-apps/dcf-crd/ for CRD examples.
  #
  # Example CRD use cases:
  #   - Namespace-specific egress rules (e.g., allow dev namespace to access test APIs)
  #   - Pod-label based policies (e.g., allow app=infosec pods to access virustotal.com)
  #   - Temporary rules for debugging/testing
  #############################

  #############################
  # DEFAULT DENY - INTENTIONALLY OMITTED
  #
  # DO NOT add a default deny rule with dst_smart_groups = public_internet (0.0.0.0/0)
  # because 0.0.0.0/0 matches ALL traffic including private RFC1918 addresses.
  # This would block inter-VPC traffic even with explicit permit rules above.
  #
  # If you need default deny for internet egress:
  #   1. Create a SmartGroup that excludes RFC1918 ranges
  #   2. Or use WebGroups with explicit deny for specific domains
  #   3. Or rely on AWS Security Groups / NACLs for internet egress control
  #############################
}

#####################
# Outputs
#####################

output "dcf_ruleset_uuid" {
  description = "UUID of the DCF ruleset"
  value       = aviatrix_dcf_ruleset.k8s_demo.id
}

output "smartgroup_cluster_vpc_uuid" {
  description = "UUID of cluster VPC SmartGroup"
  value       = aviatrix_smart_group.cluster_vpc.uuid
}

output "webgroup_github_aviatrix_uuid" {
  description = "UUID of GitHub Aviatrix WebGroup (for CRD reference)"
  value       = aviatrix_web_group.github_aviatrix.uuid
}
