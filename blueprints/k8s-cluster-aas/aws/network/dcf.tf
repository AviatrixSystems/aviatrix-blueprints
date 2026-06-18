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


#####################
# Distributed Cloud Firewall (DCF) Policies - AWS / Pattern A
#
# Pattern A: Cluster-as-a-Service
#   Each team has a dedicated EKS cluster in its own VPC.
#   DCF uses VPC-level SmartGroups for inter-team isolation.
#
# Architecture:
#   - Team-A VPC (10.10.0.0/20) - team-a EKS cluster
#   - Team-B VPC (10.11.0.0/20) - team-b EKS cluster
#   - Team-C VPC (10.12.0.0/20) - team-c EKS cluster (isolated)
#   - Database VPC (10.5.0.0/22)  - Shared database
#   - Pod CIDR (100.64.0.0/16)   - Shared across all clusters, SNAT'd to spoke GW IPs
#
# Policy Structure:
#   Priority 0-1:   Threat Prevention (GeoBlock, ThreatIQ)
#   Priority 10-11: PERMIT specific inter-team API calls
#   Priority 20-25: DENY isolated team pairs (both directions)
#   Priority 50:    PERMIT egress via WebGroups (EKS required services)
#
# IMPORTANT LESSONS LEARNED:
#   - DCF sees POST-SNAT traffic (spoke gateway IPs), not pod IPs
#   - Use VPC type SmartGroups for source matching (match by VPC name)
#   - Use Hostname SmartGroups for service destinations (FQDN pointing to internal ALB)
#   - Always deny BOTH directions explicitly between isolated teams
#   - Do NOT use 0.0.0.0/0 as default deny destination (blocks RFC1918 too)
#####################

#####################
# SmartGroups - VPC Based (Infrastructure)
# Match by VPC name for source traffic identification
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

# Aggregate SmartGroup for all EKS clusters (egress rules)
resource "aviatrix_smart_group" "all_eks_clusters" {
  name = "${local.name_prefix}-sg-all-eks-clusters"
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
# Match by DNS hostname for service-level destination targeting
#
# CRITICAL: Because DCF sees POST-SNAT traffic, source IPs are spoke GW IPs.
# Use VPC SmartGroups for source, hostname SmartGroups for destinations.
#####################

resource "aviatrix_smart_group" "team_a_service" {
  name = "${local.name_prefix}-sg-team-a-svc"
  selector {
    match_expressions {
      fqdn = "team-a.${var.private_dns_zone_name}"
    }
  }
}

resource "aviatrix_smart_group" "team_b_service" {
  name = "${local.name_prefix}-sg-team-b-svc"
  selector {
    match_expressions {
      fqdn = "team-b.${var.private_dns_zone_name}"
    }
  }
}

resource "aviatrix_smart_group" "team_c_service" {
  name = "${local.name_prefix}-sg-team-c-svc"
  selector {
    match_expressions {
      fqdn = "team-c.${var.private_dns_zone_name}"
    }
  }
}

resource "aviatrix_smart_group" "database" {
  name = "${local.name_prefix}-sg-database"
  selector {
    match_expressions {
      fqdn = "db.${var.private_dns_zone_name}"
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
  # Built-in "Public Internet" SmartGroup UUID
  # Matches all public (non-RFC1918) IPs
  public_internet_uuid = "def000ad-0000-0000-0000-000000000001"
}

#####################
# WebGroups - EKS Required Services
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/private-clusters.html
#####################

resource "aviatrix_web_group" "eks_required" {
  name = "${local.name_prefix}-wg-eks-required"
  selector {
    # ECR (Elastic Container Registry)
    match_expressions {
      snifilter = "*.dkr.ecr.*.amazonaws.com"
    }
    match_expressions {
      snifilter = "api.ecr.*.amazonaws.com"
    }

    # EKS API and Auth
    match_expressions {
      snifilter = "*.eks.amazonaws.com"
    }

    # S3 (for ECR image layers, VPC CNI, etc.)
    match_expressions {
      snifilter = "*.s3.amazonaws.com"
    }
    match_expressions {
      snifilter = "*.s3.*.amazonaws.com"
    }

    # STS (Security Token Service - for IRSA)
    match_expressions {
      snifilter = "sts.*.amazonaws.com"
    }

    # CloudWatch Logs and Monitoring
    match_expressions {
      snifilter = "logs.*.amazonaws.com"
    }
    match_expressions {
      snifilter = "monitoring.*.amazonaws.com"
    }

    # EC2 API (for VPC CNI, node management)
    match_expressions {
      snifilter = "ec2.*.amazonaws.com"
    }

    # Elastic Load Balancing (for ALB Controller)
    match_expressions {
      snifilter = "elasticloadbalancing.*.amazonaws.com"
    }

    # Route53 (for ExternalDNS)
    match_expressions {
      snifilter = "route53.amazonaws.com"
    }

    # IAM (for IRSA token validation)
    match_expressions {
      snifilter = "iam.amazonaws.com"
    }

    # SSM (for EKS managed node groups)
    match_expressions {
      snifilter = "ssm.*.amazonaws.com"
    }

    # Kubernetes Registry
    match_expressions {
      snifilter = "registry.k8s.io"
    }
    match_expressions {
      snifilter = "*.pkg.dev"
    }
    # Container registries for Calico and other non-AWS workloads
    match_expressions {
      snifilter = "docker.io"
    }
    match_expressions {
      snifilter = "*.docker.io"
    }
    match_expressions {
      snifilter = "quay.io"
    }
  }
}

resource "aviatrix_web_group" "kubernetes_io" {
  name = "${local.name_prefix}-wg-kubernetes-io"
  selector {
    match_expressions {
      snifilter = "kubernetes.io"
    }
  }
}

resource "aviatrix_web_group" "github_aviatrix" {
  name = "${local.name_prefix}-wg-github-aviatrix"
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
# DCF Ruleset
#####################

#####################
# DCF Policy Group + Ruleset
# Each blueprint creates its own policy group as a standalone attachment point.
#####################

data "aviatrix_dcf_attachment_point" "terraform_after" {
  name = "TERRAFORM_AFTER_UI_MANAGED"
}

resource "aviatrix_dcf_policy_group" "caas" {
  name      = "${local.name_prefix}-caas-group"
  attach_to = data.aviatrix_dcf_attachment_point.terraform_after.id

  ruleset_reference {
    priority    = 100
    target_uuid = aviatrix_dcf_ruleset.caas.id
  }
}

resource "aviatrix_dcf_ruleset" "caas" {
  depends_on = [time_sleep.wait_for_dcf]
  name       = "${local.name_prefix}-caas"

  #############################
  # THREAT PREVENTION (Priority 0-1)
  #############################

  rules {
    name             = "caas-block-geo"
    action           = "DENY"
    priority         = 100
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.all_eks_clusters.uuid]
    dst_smart_groups = [aviatrix_smart_group.geo_blocked.uuid]
  }

  rules {
    name             = "caas-block-threat"
    action           = "DENY"
    priority         = 101
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.all_eks_clusters.uuid]
    dst_smart_groups = [aviatrix_smart_group.threat_intel.uuid]
  }

  #############################
  # INTER-TEAM EAST-WEST (Priority 110-111)
  #
  # CRITICAL: DCF sees POST-SNAT traffic from pods
  # - Pod IP (100.64.x.x) is SNAT'd to spoke gateway IP
  # - Use VPC type SmartGroups for source matching
  # - Use Hostname SmartGroups for service destinations
  #############################

  rules {
    name             = "caas-team-a-to-team-b-api"
    action           = "PERMIT"
    priority         = 110
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_a_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_b_service.uuid]
    port_ranges {
      lo = 443
    }
  }

  rules {
    name             = "caas-team-b-to-team-a-api"
    action           = "PERMIT"
    priority         = 111
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_b_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_a_service.uuid]
    port_ranges {
      lo = 8080
    }
  }

  #############################
  # INTER-TEAM DENY (Priority 120-123)
  # CRITICAL: Always deny BOTH directions explicitly.
  #############################

  rules {
    name             = "caas-deny-a-to-c"
    action           = "DENY"
    priority         = 120
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_a_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_c_vpc.uuid]
  }

  rules {
    name             = "caas-deny-c-to-a"
    action           = "DENY"
    priority         = 121
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_c_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_a_vpc.uuid]
  }

  rules {
    name             = "caas-deny-b-to-c"
    action           = "DENY"
    priority         = 122
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_b_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_c_vpc.uuid]
  }

  rules {
    name             = "caas-deny-c-to-b"
    action           = "DENY"
    priority         = 123
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.team_c_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.team_b_vpc.uuid]
  }

  #############################
  # EGRESS - EKS Required (Priority 150)
  #############################

  rules {
    name             = "caas-egress-eks-required"
    action           = "PERMIT"
    priority         = 150
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.all_eks_clusters.uuid]
    dst_smart_groups = [local.public_internet_uuid]
    web_groups       = [aviatrix_web_group.eks_required.uuid]
    port_ranges {
      lo = 443
    }
  }

  #############################
  # DEFAULT DENY - Public Internet (Priority 200)
  # Uses built-in Public Internet SmartGroup (non-RFC1918 only).
  # Does NOT block east-west RFC1918 traffic through the transit.
  #############################

  rules {
    name             = "caas-default-deny-internet"
    action           = "DENY"
    priority         = 200
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.all_eks_clusters.uuid]
    dst_smart_groups = [local.public_internet_uuid]
  }
}

#####################
# Outputs
#####################

output "dcf_ruleset_uuid" {
  description = "UUID of the DCF ruleset"
  value       = aviatrix_dcf_ruleset.caas.id
}

output "smartgroup_team_a_vpc_uuid" {
  description = "UUID of team-a VPC SmartGroup"
  value       = aviatrix_smart_group.team_a_vpc.uuid
}

output "smartgroup_team_b_vpc_uuid" {
  description = "UUID of team-b VPC SmartGroup"
  value       = aviatrix_smart_group.team_b_vpc.uuid
}

output "smartgroup_team_c_vpc_uuid" {
  description = "UUID of team-c VPC SmartGroup"
  value       = aviatrix_smart_group.team_c_vpc.uuid
}
