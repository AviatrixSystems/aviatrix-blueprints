provider "azurerm" {
  features {}
}

provider "aviatrix" {
  controller_ip           = var.aviatrix_controller_ip
  username                = var.aviatrix_username
  password                = var.aviatrix_password
  skip_version_validation = true
}

locals {
  net = data.terraform_remote_state.network.outputs
}

module "cluster" {
  source = "../../../modules/azure-aks-cluster"

  cluster_name        = local.net.cluster_name
  azure_region        = local.net.azure_region
  resource_group_name = local.net.resource_group_name

  vnet_id             = local.net.vnet_id
  node_subnet_id      = local.net.node_subnet_id
  pod_subnet_id       = local.net.pod_subnet_id
  node_route_table_id = local.net.node_route_table_id
  pod_route_table_id  = local.net.pod_route_table_id

  kubernetes_version = var.kubernetes_version
  node_pool_config   = var.node_pool_config

  service_cidr   = local.net.service_cidr
  dns_service_ip = local.net.dns_service_ip

  authorized_ip_ranges    = var.authorized_ip_ranges
  spoke_gateway_public_ip = local.net.spoke_gateway_public_ip

  enable_aviatrix_onboarding    = var.enable_aviatrix_onboarding
  aviatrix_controller_public_ip = var.aviatrix_controller_public_ip

  tags = {
    Environment = "demo"
    Blueprint   = "azure-aks-singlecluster"
    Terraform   = "true"
  }
}
