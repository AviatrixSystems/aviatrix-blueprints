# =============================================================================
# Aviatrix Spoke Gateway: policy enforcement point for OpenClaw VM egress
# =============================================================================
module "spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud   = "AWS"
  name    = local.name
  gw_name = var.spoke_gateway_name == "" ? "${local.name}-gw" : var.spoke_gateway_name
  region  = var.aws_region
  account = var.aws_access_account

  use_existing_vpc = true
  vpc_id           = aws_vpc.this.id
  cidr             = var.vpc_cidr
  gw_subnet        = aws_subnet.gateway_public.cidr_block

  ha_gw                     = false
  instance_size             = var.spoke_gateway_size
  single_ip_snat            = var.single_ip_snat
  private_vpc_default_route = var.program_private_default_route
  enable_encrypt_volume     = var.enable_gateway_volume_encryption
  tags                      = local.common_tags

  # This is an egress-control spoke, not a transit-attached spoke by default.
  attached = false

  depends_on = [
    aws_route_table_association.gateway_public,
    aws_route_table_association.agent_private
  ]
}
