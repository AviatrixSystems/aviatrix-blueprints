#####################
# Aviatrix Transit Gateway
#####################

module "aws_transit" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "~> 8.0"

  name    = "${var.name_prefix}-transit"
  cloud   = "AWS"
  account = var.aviatrix_aws_account_name
  region  = var.aws_region
  cidr    = var.transit_cidr
  ha_gw   = false

  instance_size     = "t3.medium"
  connected_transit = true

  enable_vpc_dns_server = true
}

#####################
# Aviatrix Spoke Gateway (HA Pair)
#####################

module "spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  cloud      = "AWS"
  name       = "${var.name_prefix}-spoke"
  account    = var.aviatrix_aws_account_name
  region     = var.aws_region
  transit_gw = module.aws_transit.transit_gateway.gw_name

  instance_size  = "t3.medium"
  ha_gw          = false # Temporarily disabled - controller HA enablement failing
  single_ip_snat = true

  enable_vpc_dns_server = true

  # Use existing VPC created above
  use_existing_vpc = true
  vpc_id           = aws_vpc.this.id
  gw_subnet        = aws_subnet.avx_public[0].cidr_block
  hagw_subnet      = aws_subnet.avx_public[1].cidr_block

  skip_public_route_table_update = false
}

#####################
# Aviatrix K8s Cluster Onboarding
#####################

resource "aviatrix_kubernetes_cluster" "this" {
  cluster_id          = module.eks.cluster_arn
  use_csp_credentials = true

  depends_on = [module.eks]
}

# EKS access entry for Aviatrix Controller
resource "aws_eks_access_entry" "aviatrix_controller" {
  count = var.aviatrix_controller_role_arn != "" ? 1 : 0

  cluster_name      = module.eks.cluster_name
  principal_arn     = var.aviatrix_controller_role_arn
  kubernetes_groups = ["view-nodes"]
  type              = "STANDARD"

  depends_on = [module.eks]
}

resource "aws_eks_access_policy_association" "aviatrix_controller" {
  count = var.aviatrix_controller_role_arn != "" ? 1 : 0

  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  principal_arn = var.aviatrix_controller_role_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.aviatrix_controller]
}
