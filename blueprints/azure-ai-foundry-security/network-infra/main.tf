# ══════════════════════════════════════════════════════════════════════════════
# Azure Network Infrastructure
# ══════════════════════════════════════════════════════════════════════════════

data "azurerm_location" "current" {
  location = var.location
}

resource "azurerm_resource_group" "main" {
  name     = "${var.resource_group_name}-${local.suffix}"
  location = var.location
  tags     = local.tags
}

# ── VNet ──────────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "main" {
  name                = "${var.vnet_name}-${local.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.vnet_address_space]
  tags                = local.tags
}

# ── Route tables (one per subnet) ─────────────────────────────────────────────
# Routes managed outside Terraform (BGP / Aviatrix), ignore drift.

resource "azurerm_route_table" "private_endpoint" {
  name                = "${var.vnet_name}-rt-snet-private-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags

  route {
    name           = "default-blackhole"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }

  lifecycle {
    ignore_changes = [route]
  }
}

resource "azurerm_route_table" "foundry_agent" {
  name                = "${var.vnet_name}-rt-snet-foundry-agent"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags

  route {
    name           = "default-blackhole"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }

  lifecycle {
    ignore_changes = [route]
  }
}

resource "azurerm_route_table" "avx_spoke_gw" {
  name                = "${var.vnet_name}-rt-snet-avx-spoke-gw"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags

  route {
    name           = "default-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }

  lifecycle {
    ignore_changes = [route]
  }
}

# ── Subnets ───────────────────────────────────────────────────────────────────
# Subnet names need no random suffix — they are scoped inside the VNet and cannot collide across deployments.

resource "azurerm_subnet" "avx_spoke_gw" {
  name                 = "${var.vnet_name}-snet-avx-spoke-gw"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space, 5, 0)]
}

resource "azurerm_subnet" "private_endpoint" {
  name                 = "${var.vnet_name}-snet-private-endpoint"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space, 5, 1)]
}

resource "azurerm_subnet_route_table_association" "avx_spoke_gw" {
  subnet_id      = azurerm_subnet.avx_spoke_gw.id
  route_table_id = azurerm_route_table.avx_spoke_gw.id
}

resource "azurerm_subnet_route_table_association" "private_endpoint" {
  subnet_id      = azurerm_subnet.private_endpoint.id
  route_table_id = azurerm_route_table.private_endpoint.id
}

resource "azurerm_subnet" "foundry_agent" {
  name                 = "${var.vnet_name}-snet-foundry-agent"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space, 1, 1)]

  private_endpoint_network_policies = "Enabled"

  delegation {
    name = "Microsoft.App-environments"
    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_subnet_route_table_association" "foundry_agent" {
  subnet_id      = azurerm_subnet.foundry_agent.id
  route_table_id = azurerm_route_table.foundry_agent.id
}

# ── Private DNS zones + VNet links ────────────────────────────────────────────

resource "azurerm_private_dns_zone" "zones" {
  for_each            = toset(local.private_dns_zones)
  name                = each.key
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "links" {
  for_each              = toset(local.private_dns_zones)
  name                  = "link-${replace(each.key, ".", "-")}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.zones[each.key].name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = local.tags
}

# ══════════════════════════════════════════════════════════════════════════════
# Aviatrix Spoke Gateway
# ══════════════════════════════════════════════════════════════════════════════

resource "aviatrix_spoke_gateway" "spoke" {
  cloud_type     = 8 # Azure
  account_name   = var.avx_account_name
  gw_name        = "${var.avx_gw_name}-${local.suffix}"
  vpc_id         = "${azurerm_virtual_network.main.name}:${azurerm_subnet.avx_spoke_gw.resource_group_name}:${azurerm_virtual_network.main.guid}"
  vpc_reg        = data.azurerm_location.current.display_name
  subnet         = azurerm_subnet.avx_spoke_gw.address_prefixes[0]
  gw_size        = var.avx_gw_size
  single_ip_snat = true
  tags           = local.tags

  depends_on = [
    azurerm_subnet_route_table_association.avx_spoke_gw,
  ]
}

resource "aviatrix_spoke_transit_attachment" "main" {
  count           = var.avx_transit_gw_name != "donotattach" ? 1 : 0
  spoke_gw_name   = aviatrix_spoke_gateway.spoke.gw_name
  transit_gw_name = var.avx_transit_gw_name
}

# ══════════════════════════════════════════════════════════════════════════════
# Aviatrix DCF — Smart Groups, Web Groups, Ruleset
# ══════════════════════════════════════════════════════════════════════════════

# ── Smart group — Foundry Agent subnet ───────────────────────────────────────

resource "aviatrix_smart_group" "foundry_agent" {
  name = "sg-foundry-agents-${local.suffix}"

  selector {
    match_expressions {
      type         = "subnet"
      account_name = var.avx_account_name
      name         = azurerm_subnet.foundry_agent.name
    }
  }
}

# ── Smart group — ACA platform Service Tags (DECRYPT_NOT_ALLOWED) ────────────

resource "aviatrix_smart_group" "aca_platform_svctags" {
  name = "sg-aca-platform-svctags-${local.suffix}"

  selector {
    dynamic "match_expressions" {
      for_each = var.aca_platform_svc_tags
      content {
        external = "azureips"
        ext_args = {
          service_name = match_expressions.value
        }
      }
    }
  }
}

# ── Web group — ACA runtime FQDNs (bypassed for decryption) ──────────────────
# Source: https://learn.microsoft.com/en-us/azure/container-apps/use-azure-firewall

resource "aviatrix_web_group" "aca_requirements_fqdns" {
  name = "wg-aca-requirements-fqdns-${local.suffix}"

  selector {
    dynamic "match_expressions" {
      for_each = var.aca_requirements_fqdns
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

# ── Web group — approved tool-call FQDNs (TLS decrypted and inspected) ───────
# Add sanctioned MCP server FQDNs and external API endpoints here.

resource "aviatrix_web_group" "foundry_tool_calls" {
  name = "wg-foundry-tool-calls-${local.suffix}"

  selector {
    dynamic "match_expressions" {
      for_each = var.tool_call_fqdns
      content {
        snifilter = match_expressions.value
      }
    }
  }
}

# ── DCF attachment point ──────────────────────────────────────────────────────

data "aviatrix_dcf_attachment_point" "tf_before_ui" {
  name = "TERRAFORM_BEFORE_UI_MANAGED"
}

# ── DCF ruleset — Foundry Agent egress ───────────────────────────────────────

resource "aviatrix_dcf_ruleset" "foundry_agent" {
  name      = "rs-foundry-agent-egress-${local.suffix}"
  attach_to = data.aviatrix_dcf_attachment_point.tf_before_ui.id

  # Rule 1 — deny known-malicious destinations before any permit (ThreatGroup)
  rules {
    name             = "foundry-deny-threat-intel-${local.suffix}"
    priority         = 1
    action           = "DENY"
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.foundry_agent.uuid]
    dst_smart_groups = [local.sg_threat_intel]
  }

  # Rule 2 — ACA runtime FQDNs: permit without decryption (TLS break breaks ACA startup)
  rules {
    name                 = "aca-requirements-fqdn-${local.suffix}"
    priority             = 2
    action               = "PERMIT"
    decrypt_policy       = "DECRYPT_NOT_ALLOWED"
    protocol             = "TCP"
    flow_app_requirement = "TLS_REQUIRED"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.foundry_agent.uuid]
    dst_smart_groups     = [local.sg_public_internet]
    web_groups           = [aviatrix_web_group.aca_requirements_fqdns.uuid]
    port_ranges {
      lo = 443
      hi = 443
    }
  }

  # Rule 3 — ACA runtime Service Tags: permit without decryption (control-plane, not tool-call surface)
  rules {
    name                 = "aca-requirements-svctag-${local.suffix}"
    priority             = 3
    action               = "PERMIT"
    decrypt_policy       = "DECRYPT_NOT_ALLOWED"
    protocol             = "TCP"
    flow_app_requirement = "TLS_REQUIRED"
    logging              = true
    src_smart_groups     = [aviatrix_smart_group.foundry_agent.uuid]
    dst_smart_groups     = [aviatrix_smart_group.aca_platform_svctags.uuid]
    port_ranges {
      lo = 443
      hi = 443
    }
  }

  # Rule 4 — approved tool-call FQDNs: permit (always enforced)
  rules {
    name             = "foundry-tool-calls-${local.suffix}"
    priority         = 4
    action           = "PERMIT"
    watch            = false
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.foundry_agent.uuid]
    dst_smart_groups = [local.sg_public_internet]
    web_groups       = [aviatrix_web_group.foundry_tool_calls.uuid]
    port_ranges {
      lo = 443
      hi = 443
    }
  }

  # Rule 5 — no-zero-trust: permit all web destinations (AllWeb) — comment out to demo DCF protection
  rules {
    name             = "no-zero-trust-${local.suffix}"
    priority         = 5
    action           = "PERMIT"
    protocol         = "TCP"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.foundry_agent.uuid]
    dst_smart_groups = [local.sg_public_internet]
    web_groups       = [local.wg_allweb]
    port_ranges {
      lo = 80
      hi = 80
    }
    port_ranges {
      lo = 443
      hi = 443
    }
  }

  # Rule 6 — default deny internet: any unlisted FQDN/destination not matched above
  rules {
    name             = "foundry-deny-internet-${local.suffix}"
    priority         = 6
    action           = "DENY"
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.foundry_agent.uuid]
    dst_smart_groups = [local.sg_public_internet]
  }

  # Rule 7 — default deny East-West: no lateral movement from agent subnet to adjacent spokes
  rules {
    name             = "foundry-deny-east-west-${local.suffix}"
    priority         = 7
    action           = "DENY"
    protocol         = "ANY"
    logging          = true
    src_smart_groups = [aviatrix_smart_group.foundry_agent.uuid]
    dst_smart_groups = [local.sg_any]
  }
}
