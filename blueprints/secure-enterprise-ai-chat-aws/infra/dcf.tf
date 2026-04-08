#####################
# Distributed Cloud Firewall (DCF) - Egress Control
#
# Controls which external services the AI workloads can reach.
# Primary use case: restrict LLM API egress to approved providers only.
#
# Policy Structure:
#   1. Threat Prevention (GeoBlock, ThreatIQ) - Priority 0-9
#   2. EKS Required Services - Priority 10-19
#   3. AI Service Egress (Bedrock, etc.) - Priority 20-29
#   4. K8s CRD Placeholder - Priority 50-99
#####################

#####################
# SmartGroups
#####################

# VPC-type: matches the entire AI VPC by cloud resource ID
resource "aviatrix_smart_group" "ai_vpc" {
  name = "sg-${var.name_prefix}-vpc"
  selector {
    match_expressions {
      type   = "vpc"
      res_id = aws_vpc.this.id
    }
  }
}

# K8s-type: LiteLLM pods (the only component that needs Bedrock egress)
resource "aviatrix_smart_group" "k8s_litellm" {
  name = "sg-${var.name_prefix}-k8s-litellm"
  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = module.eks.cluster_arn
      k8s_namespace  = "default"
      k8s_service    = "litellm"
    }
  }
  depends_on = [aviatrix_kubernetes_cluster.this]
}

# K8s-type: LibreChat pods (frontend, needs outbound for ALB health checks only)
resource "aviatrix_smart_group" "k8s_librechat" {
  name = "sg-${var.name_prefix}-k8s-librechat"
  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = module.eks.cluster_arn
      k8s_namespace  = "default"
      k8s_service    = "librechat"
    }
  }
  depends_on = [aviatrix_kubernetes_cluster.this]
}

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

locals {
  public_internet_uuid = "def000ad-0000-0000-0000-000000000001"
}

#####################
# WebGroups - AI Service Endpoints
#####################

resource "aviatrix_web_group" "aws_bedrock" {
  name = "wg-aws-bedrock"
  selector {
    match_expressions {
      snifilter = "bedrock-runtime.*.amazonaws.com"
    }
    match_expressions {
      snifilter = "bedrock.*.amazonaws.com"
    }
  }
}

#####################
# WebGroups - EKS Required Services
#####################

resource "aviatrix_web_group" "eks_required" {
  name = "wg-eks-required"
  selector {
    # ECR - AWS EKS managed account
    match_expressions {
      snifilter = "602401143452.dkr.ecr.*.amazonaws.com"
    }
    match_expressions {
      snifilter = "api.ecr.*.amazonaws.com"
    }
    # ECR Public
    match_expressions {
      snifilter = "public.ecr.aws"
    }
    match_expressions {
      snifilter = "api.ecr-public.*.amazonaws.com"
    }
    # S3 - AWS-owned buckets
    match_expressions {
      snifilter = "al2023-repos-*.s3.dualstack.*.amazonaws.com"
    }
    match_expressions {
      snifilter = "prod-registry-k8s-io-*.s3.dualstack.*.amazonaws.com"
    }
    match_expressions {
      snifilter = "prod-*-starport-layer-bucket.s3.*.amazonaws.com"
    }
    # EC2 APIs
    match_expressions {
      snifilter = "ec2.*.amazonaws.com"
    }
    # STS
    match_expressions {
      snifilter = "sts.*.amazonaws.com"
    }
    # EKS API
    match_expressions {
      snifilter = "*.eks.amazonaws.com"
    }
    # Elastic Load Balancing (ALB controller)
    match_expressions {
      snifilter = "elasticloadbalancing.*.amazonaws.com"
    }
    # WAFv2 / Shield (ALB controller)
    match_expressions {
      snifilter = "wafv2.*.amazonaws.com"
    }
    match_expressions {
      snifilter = "shield.*.amazonaws.com"
    }
    # CloudFront CDN (ECR/EKS layers)
    match_expressions {
      snifilter = "*.cloudfront.net"
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

#####################
# WebGroups - Container Registries (for LibreChat/LiteLLM images)
#####################

resource "aviatrix_web_group" "container_registries" {
  name = "wg-container-registries"
  selector {
    # GitHub Container Registry (LibreChat, LiteLLM)
    match_expressions {
      snifilter = "ghcr.io"
    }
    match_expressions {
      snifilter = "*.ghcr.io"
    }
    # Docker Hub (MongoDB, utilities)
    match_expressions {
      snifilter = "registry-1.docker.io"
    }
    match_expressions {
      snifilter = "auth.docker.io"
    }
    match_expressions {
      snifilter = "production.cloudflare.docker.com"
    }
  }
}

#####################
# DCF Ruleset
#####################

resource "aviatrix_dcf_ruleset" "ai_egress" {
  name      = "${var.name_prefix}-egress-control"
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
    src_smart_groups = [aviatrix_smart_group.ai_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.geo_blocked.uuid]
  }

  rules {
    name             = "Block Threat Intel IPs"
    action           = "DENY"
    priority         = 1
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.ai_vpc.uuid]
    dst_smart_groups = [aviatrix_smart_group.threat_intel.uuid]
  }

  #############################
  # EKS REQUIRED (Priority 10-19)
  #############################

  rules {
    name                 = "EKS Required AWS Services"
    action               = "PERMIT"
    priority             = 10
    protocol             = "TCP"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.ai_vpc.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.eks_required.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  rules {
    name                 = "Container Registries - GHCR, Docker Hub"
    action               = "PERMIT"
    priority             = 11
    protocol             = "TCP"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.ai_vpc.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.container_registries.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  #############################
  # AI SERVICE EGRESS (Priority 20-29)
  # Explicitly allow only approved AI backends
  #############################

  rules {
    name                 = "Allow AWS Bedrock - LiteLLM Only"
    action               = "PERMIT"
    priority             = 20
    protocol             = "TCP"
    logging              = true
    watch                = true
    src_smart_groups     = [aviatrix_smart_group.k8s_litellm.uuid]
    dst_smart_groups     = [local.public_internet_uuid]
    web_groups           = [aviatrix_web_group.aws_bedrock.uuid]
    flow_app_requirement = "APP_UNSPECIFIED"
    port_ranges {
      lo = 443
    }
  }

  #############################
  # K8s CRD PLACEHOLDER (Priority 50-99)
  #
  # Use Aviatrix K8s Firewall CRDs to add namespace-level egress rules.
  # Example: allow a specific namespace to reach additional AI APIs.
  #############################

  #############################
  # DEFAULT DENY (Priority 100)
  # Zero-trust: block all egress not explicitly permitted above.
  # If something breaks, check logs and add a PERMIT rule above this.
  #############################

  rules {
    name             = "Default Deny All Egress"
    action           = "DENY"
    priority         = 100
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.ai_vpc.uuid]
    dst_smart_groups = [local.public_internet_uuid]
  }
}
