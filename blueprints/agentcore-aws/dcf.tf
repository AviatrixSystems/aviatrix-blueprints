# =============================================================================
# Distributed Cloud Firewall policy for the AgentCore VCA
#
# SmartGroups
#   sg-agentcore-runtime-subnet  (source)  subnet-type, matches egress from
#                                           the AgentCore runtime subnet
#   sg-agentcore-endpoint-data    (dest)    fqdn-type, matches the data-plane
#                                           PrivateLink hostname
#   sg-agentcore-endpoint-control (dest)    fqdn-type, matches the control-plane
#                                           PrivateLink hostname
#   sg-client-spoke               (source)  vpc-type, matches the client spoke
#   sg-any                        (dest)    0.0.0.0/0 catch-all used by the
#                                           default-deny rule
#
# WebGroups (destination, SNI-matched on 443/TCP)
#   wg-allowed-models      - sanctioned Bedrock / other model-provider domains
#   wg-allowed-tools       - sanctioned tool-call domains
#   wg-aws-control-domains - STS, CWLogs, X-Ray, Secrets Manager
#
# Policy ordering (first-match):
#   10  allow client-spoke -> PrivateLink data/control (ingress pattern)
#   30  allow runtime subnet -> allowed-models   (WebGroup, log, SNI verify)
#   31  allow runtime subnet -> allowed-tools    (WebGroup, log, SNI verify)
#   32  allow runtime subnet -> aws control      (WebGroup, log)
#   50  deny   runtime subnet -> any on 53/UDP   (DNS exfil block)
#   100 deny   runtime subnet -> any             (default deny, logs everything
#                                                  blocked)
# =============================================================================

# -----------------------------------------------------------------------------
# SmartGroups
# -----------------------------------------------------------------------------

# Source SmartGroup: AgentCore runtime subnet (10.50.10.0/24 by default).
# type = "subnet" requires vpc_id + cidr per the provider schema in 8.x.
resource "aviatrix_smart_group" "agentcore_runtime_subnet" {
  name = "${var.name_prefix}-runtime-subnet"

  selector {
    match_expressions {
      type   = "subnet"
      res_id = aws_subnet.agentcore_runtime.id
    }
  }

  depends_on = [module.spoke_agentcore]
}

# Destination SmartGroup: the AgentCore data-plane PrivateLink endpoint.
# We match the AWS-managed *.vpce.amazonaws.com hostname instead of the
# user-facing bedrock-agentcore.<region>.amazonaws.com name because the
# vpce hostname is publicly resolvable - AWS returns the endpoint's private
# IPs in public DNS - so the Aviatrix gateway's default DNS resolves it
# without requiring the gateway to share our Route 53 Private Hosted Zone.
# Client workloads still see the user-facing name via the PHZ association.
resource "aviatrix_smart_group" "agentcore_endpoint_data" {
  name = "${var.name_prefix}-agentcore-data-host"

  selector {
    match_expressions {
      fqdn = aws_vpc_endpoint.agentcore_data.dns_entry[0].dns_name
    }
  }
}

resource "aviatrix_smart_group" "agentcore_endpoint_control" {
  name = "${var.name_prefix}-agentcore-control-host"

  selector {
    match_expressions {
      fqdn = aws_vpc_endpoint.agentcore_control.dns_entry[0].dns_name
    }
  }
}

# Source SmartGroup: the client spoke VPC (where the invoker EC2 lives)
resource "aviatrix_smart_group" "client_spoke" {
  name = "${var.name_prefix}-client-spoke"

  selector {
    match_expressions {
      type = "vpc"
      name = "${var.name_prefix}-client-spoke"
    }
  }

  depends_on = [module.spoke_client]
}

# Any-destination SmartGroup for the default-deny rule
resource "aviatrix_smart_group" "any" {
  name = "${var.name_prefix}-any"

  selector {
    match_expressions {
      cidr = "0.0.0.0/0"
    }
  }
}

# FQDN SmartGroup scoped to just the GitHub hosts we URL-filter on. The
# URL-filter deny rule at priority 29 uses this as dst so decryption only
# kicks in for flows to these domains. Without this narrowing, every
# 443/TCP flow from the runtime subnet would be MITM'd (including ECR and
# Bedrock), breaking the microVM's own image pull and model calls.
resource "aviatrix_smart_group" "github_hosts" {
  name = "${var.name_prefix}-github-hosts"

  selector {
    match_expressions {
      fqdn = "api.github.com"
    }
    match_expressions {
      fqdn = "raw.githubusercontent.com"
    }
    match_expressions {
      fqdn = "github.com"
    }
  }
}

# -----------------------------------------------------------------------------
# WebGroups (SNI filters on 443/TCP egress)
# -----------------------------------------------------------------------------

resource "aviatrix_web_group" "allowed_models" {
  name = "${var.name_prefix}-allowed-models"

  dynamic "selector" {
    for_each = [1]
    content {
      dynamic "match_expressions" {
        for_each = var.allowed_model_domains
        content {
          snifilter = match_expressions.value
        }
      }
    }
  }
}

resource "aviatrix_web_group" "allowed_tools" {
  name = "${var.name_prefix}-allowed-tools"

  dynamic "selector" {
    for_each = [1]
    content {
      dynamic "match_expressions" {
        for_each = var.allowed_tool_domains
        content {
          snifilter = match_expressions.value
        }
      }
    }
  }
}

resource "aviatrix_web_group" "aws_control" {
  name = "${var.name_prefix}-aws-control-domains"

  dynamic "selector" {
    for_each = [1]
    content {
      dynamic "match_expressions" {
        for_each = var.aws_control_domains
        content {
          snifilter = match_expressions.value
        }
      }
    }
  }
}

# URL-path-filtered IoC WebGroup. Each match_expressions pair is an
# (SNI, URL) tuple that must BOTH match. Designed for decrypted rules only;
# requires the parent policy to set decrypt_policy = DECRYPT_ALLOWED and
# reference the default TLS profile (or a custom one). See dcf.tf policy
# priority 29 below.
#
# Seeded with Shai-Hulud (Sep 2025 npm worm) indicators. Append new entries
# from Unit 42 / GitHub Security Advisory / npm audit feeds as they surface.
resource "aviatrix_web_group" "supply_chain_ioc_github" {
  name = "${var.name_prefix}-supply-chain-ioc-github"

  # Aviatrix `urlfilter` matches against <host>/<path> - a single match
  # expression cannot combine snifilter + urlfilter (enforced by the API).
  # Scope each pattern by baking the host into the URL.
  selector {
    match_expressions {
      urlfilter = "api.github.com/repos/*/*shai-hulud*"
    }
    match_expressions {
      urlfilter = "api.github.com/repos/*shai-hulud*/*"
    }
    match_expressions {
      urlfilter = "raw.githubusercontent.com/*/*shai-hulud*"
    }
    match_expressions {
      urlfilter = "github.com/*/*shai-hulud*"
    }
    match_expressions {
      urlfilter = "github.com/*shai-hulud*"
    }
    match_expressions {
      urlfilter = "github.com/shai-hulud*"
    }
  }
}

resource "aviatrix_web_group" "allowed_mcp_servers" {
  name = "${var.name_prefix}-allowed-mcp-servers"

  dynamic "selector" {
    for_each = [1]
    content {
      dynamic "match_expressions" {
        # Union of the user-provided allowlist with the demo adversary
        # Lambda Function URL (so the LLM05 scenario can connect to our
        # "compromised but trusted" MCP source).
        for_each = toset(concat(var.allowed_mcp_server_domains, [local.adversary_mcp_host]))
        content {
          snifilter = match_expressions.value
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Policy List
# -----------------------------------------------------------------------------

resource "aviatrix_distributed_firewalling_policy_list" "main" {
  depends_on = [
    aviatrix_distributed_firewalling_config.this,
    aviatrix_smart_group.agentcore_runtime_subnet,
    aviatrix_smart_group.agentcore_endpoint_data,
    aviatrix_smart_group.agentcore_endpoint_control,
    aviatrix_smart_group.client_spoke,
    aviatrix_smart_group.any,
    aviatrix_smart_group.github_hosts,
    aviatrix_web_group.allowed_models,
    aviatrix_web_group.allowed_tools,
    aviatrix_web_group.aws_control,
    aviatrix_web_group.allowed_mcp_servers,
    aviatrix_web_group.supply_chain_ioc_github,
  ]

  # Default TLS profile UUID - used by decryption-enabled policies below.
  # Change to a custom aviatrix_dcf_tls_profile UUID for stricter origin
  # cert validation (LOG_ONLY -> ENFORCE).


  # ---- 10: ingress from client spoke to the data-plane PrivateLink ---------
  policies {
    name     = "${var.name_prefix}-10-client-to-agentcore-data"
    action   = "PERMIT"
    priority = 10
    protocol = "TCP"
    logging  = true
    watch    = false

    src_smart_groups = [aviatrix_smart_group.client_spoke.uuid]
    dst_smart_groups = [aviatrix_smart_group.agentcore_endpoint_data.uuid]

    port_ranges {
      lo = 443
    }
  }

  # ---- 11: ingress from client spoke to the control-plane PrivateLink ------
  policies {
    name     = "${var.name_prefix}-11-client-to-agentcore-control"
    action   = "PERMIT"
    priority = 11
    protocol = "TCP"
    logging  = true
    watch    = false

    src_smart_groups = [aviatrix_smart_group.client_spoke.uuid]
    dst_smart_groups = [aviatrix_smart_group.agentcore_endpoint_control.uuid]

    port_ranges {
      lo = 443
    }
  }

  # ---- 29: URL-path deny for supply-chain IoC (Shai-Hulud npm worm + vari-
  # ants). Scoped to GitHub FQDNs so decryption is triggered only for
  # flows to those hosts - ECR/S3/Bedrock continue to pass through
  # encrypted via rules 30/32/33.
  policies {
    name     = "${var.name_prefix}-29-runtime-deny-supply-chain-ioc-github"
    action   = "DENY"
    priority = 29
    protocol = "TCP"
    logging  = true
    watch    = false

    src_smart_groups = [aviatrix_smart_group.agentcore_runtime_subnet.uuid]
    dst_smart_groups = [aviatrix_smart_group.github_hosts.uuid]
    web_groups       = [aviatrix_web_group.supply_chain_ioc_github.uuid]

    decrypt_policy = "DECRYPT_ALLOWED"
    tls_profile    = "def000ad-6000-0000-0000-000000000001" # controller default TLS profile

    port_ranges {
      lo = 443
    }
  }

  # ---- 30: egress from runtime subnet to sanctioned model-provider domains -
  # DECRYPT_NOT_ALLOWED - Bedrock SDK uses AWS SigV4 and is sensitive to
  # cert-chain changes. Decryption not required for this rule's enforcement.
  policies {
    name     = "${var.name_prefix}-30-runtime-to-allowed-models"
    action   = "PERMIT"
    priority = 30
    protocol = "TCP"
    logging  = true
    watch    = false

    src_smart_groups = [aviatrix_smart_group.agentcore_runtime_subnet.uuid]
    dst_smart_groups = [aviatrix_smart_group.any.uuid]
    web_groups       = [aviatrix_web_group.allowed_models.uuid]

    decrypt_policy = "DECRYPT_NOT_ALLOWED"

    port_ranges {
      lo = 443
    }
  }

  # ---- 31: egress from runtime subnet to sanctioned tool-call domains ------
  # Decryption enabled so rule 29's URL filter is consistent on these hosts.
  # Scoped dst to github_hosts so only github flows are decrypted.
  policies {
    name     = "${var.name_prefix}-31-runtime-to-allowed-tools"
    action   = "PERMIT"
    priority = 31
    protocol = "TCP"
    logging  = true
    watch    = false

    src_smart_groups = [aviatrix_smart_group.agentcore_runtime_subnet.uuid]
    dst_smart_groups = [aviatrix_smart_group.github_hosts.uuid]
    web_groups       = [aviatrix_web_group.allowed_tools.uuid]

    decrypt_policy = "DECRYPT_ALLOWED"
    tls_profile    = "def000ad-6000-0000-0000-000000000001"

    port_ranges {
      lo = 443
    }
  }

  # ---- 32: egress from runtime subnet to AWS control-plane service APIs ----
  # Explicit DECRYPT_NOT_ALLOWED - AWS service endpoints (ECR, S3 layer
  # buckets, STS, CloudWatch) fail TLS verification when MITM'd, and the
  # microVM's image-pull path predates the container trust store so we
  # can't plant our CA there. Keep this flow encrypted end-to-end.
  policies {
    name     = "${var.name_prefix}-32-runtime-to-aws-control"
    action   = "PERMIT"
    priority = 32
    protocol = "TCP"
    logging  = true
    watch    = false

    src_smart_groups = [aviatrix_smart_group.agentcore_runtime_subnet.uuid]
    dst_smart_groups = [aviatrix_smart_group.any.uuid]
    web_groups       = [aviatrix_web_group.aws_control.uuid]

    decrypt_policy = "DECRYPT_NOT_ALLOWED"

    port_ranges {
      lo = 443
    }
  }

  # ---- 33: egress from runtime subnet to sanctioned remote MCP servers -----
  # DECRYPT_NOT_ALLOWED for now - the mcp-python streamable-http client
  # validates the server's cert against certifi; MITM would break it.
  # When we add URL-level policy on MCP flows, we'll flip this to ALLOWED
  # and bake the MITM CA into the mcp client's trust store.
  policies {
    name     = "${var.name_prefix}-33-runtime-to-allowed-mcp-servers"
    action   = "PERMIT"
    priority = 33
    protocol = "TCP"
    logging  = true
    watch    = false

    src_smart_groups = [aviatrix_smart_group.agentcore_runtime_subnet.uuid]
    dst_smart_groups = [aviatrix_smart_group.any.uuid]
    web_groups       = [aviatrix_web_group.allowed_mcp_servers.uuid]

    decrypt_policy = "DECRYPT_NOT_ALLOWED"

    port_ranges {
      lo = 443
    }
  }

  # ---- 50: DNS exfil block - deny 53/UDP out of the runtime subnet ---------
  # Covers the Unit 42 "AgentCore Sandbox DNS tunneling" pattern. The agent
  # legitimately needs DNS to the VPC resolver (169.254.169.253) for AWS SDK
  # calls; that's intra-VPC and does not transit the spoke gateway, so this
  # rule does not block it.
  policies {
    name     = "${var.name_prefix}-50-runtime-dns-exfil-deny"
    action   = "DENY"
    priority = 50
    protocol = "UDP"
    logging  = true
    watch    = false

    src_smart_groups = [aviatrix_smart_group.agentcore_runtime_subnet.uuid]
    dst_smart_groups = [aviatrix_smart_group.any.uuid]

    port_ranges {
      lo = 53
    }
  }

  # ---- 100: default deny catch-all for runtime egress ----------------------
  policies {
    name     = "${var.name_prefix}-100-runtime-default-deny"
    action   = "DENY"
    priority = 100
    protocol = "ANY"
    logging  = true
    watch    = false

    src_smart_groups = [aviatrix_smart_group.agentcore_runtime_subnet.uuid]
    dst_smart_groups = [aviatrix_smart_group.any.uuid]
  }
}
