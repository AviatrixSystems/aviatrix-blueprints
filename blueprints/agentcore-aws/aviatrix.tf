# =============================================================================
# Aviatrix transit + two spoke gateways (no HA on any)
#
# The spoke gateways sit in-path for all private-subnet traffic in their VPCs.
# With single_ip_snat = true, the spoke GW also provides source-NAT for
# internet-bound traffic after DCF inspection. No separate NAT Gateway.
# =============================================================================

module "transit" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "~> 8.0"

  name    = "${var.name_prefix}-transit"
  cloud   = "AWS"
  account = var.aviatrix_aws_account_name
  region  = var.aws_region
  cidr    = var.transit_cidr

  ha_gw         = false
  instance_size = var.gateway_size

  # enable_vpc_dns_server requires the controller's DNS health check to pass
  # against the VPC resolver. Disabled to keep the lab deploy deterministic.
  enable_vpc_dns_server = false
  connected_transit     = true
}

module "spoke_agentcore" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  name       = "${var.name_prefix}-agentcore-spoke"
  cloud      = "AWS"
  account    = var.aviatrix_aws_account_name
  region     = var.aws_region
  transit_gw = module.transit.transit_gateway.gw_name

  ha_gw         = false
  instance_size = var.gateway_size
  # Decryption (9.0) and single_ip_snat are mutually-exclusive on the
  # same spoke gateway today - the controller's enable_decryption flow
  # disables SNAT to avoid conflicts with learned default routes. Keep
  # this at false to match the controller's post-decryption-enable state.
  # Internet egress continues to function via the transit's egress path.
  single_ip_snat = false

  enable_vpc_dns_server = false

  use_existing_vpc = true
  vpc_id           = aws_vpc.agentcore.id
  gw_subnet        = aws_subnet.agentcore_gw.cidr_block
}

module "spoke_client" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  name       = "${var.name_prefix}-client-spoke"
  cloud      = "AWS"
  account    = var.aviatrix_aws_account_name
  region     = var.aws_region
  transit_gw = module.transit.transit_gateway.gw_name

  ha_gw         = false
  instance_size = var.gateway_size
  # Decryption (9.0) and single_ip_snat are mutually-exclusive on the
  # same spoke gateway today - the controller's enable_decryption flow
  # disables SNAT to avoid conflicts with learned default routes. Keep
  # this at false to match the controller's post-decryption-enable state.
  # Internet egress continues to function via the transit's egress path.
  single_ip_snat = false

  enable_vpc_dns_server = false

  use_existing_vpc = true
  vpc_id           = aws_vpc.client.id
  gw_subnet        = aws_subnet.client_gw.cidr_block
}

# Enable Distributed Cloud Firewall globally on the controller. Policies are
# attached via aviatrix_distributed_firewalling_policy_list in dcf.tf.
resource "aviatrix_distributed_firewalling_config" "this" {
  enable_distributed_firewalling = true

  depends_on = [
    module.spoke_agentcore,
    module.spoke_client,
  ]
}
