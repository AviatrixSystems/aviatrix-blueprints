# =============================================================================
# Aviatrix Spoke Gateway
# =============================================================================

module "spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud   = "AWS"
  name    = "${local.name}-spoke"
  region  = var.aws_region
  account = var.aws_access_account

  use_existing_vpc = true
  vpc_id           = module.vpc.vpc_id
  cidr             = var.vpc_cidr
  gw_subnet        = module.vpc.public_subnets_cidr_blocks[0]

  ha_gw          = false
  single_ip_snat = true
  attached       = false
}
