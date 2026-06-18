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
  cluster_name = var.name_prefix

  common_tags = {
    Environment = "demo"
    Blueprint   = "azure-aks-singlecluster"
    Terraform   = "true"
  }
}

module "spoke_vnet" {
  source = "../../../modules/azure-aks-spoke-vnet"

  name         = var.name_prefix
  cluster_name = local.cluster_name
  vnet_cidr    = var.vnet_cidr
  pod_cidr     = var.pod_cidr

  azure_region          = var.azure_region
  aviatrix_azure_region = var.aviatrix_azure_region

  aviatrix_azure_account_name = var.aviatrix_azure_account_name
  transit_type                = var.transit_type
  transit_gw_name             = var.transit_gw_name

  tags = local.common_tags
}
