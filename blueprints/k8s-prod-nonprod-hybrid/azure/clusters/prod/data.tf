# -----------------------------------------------------------------------------
# Pattern C: AKS Production Cluster — Data Sources
# -----------------------------------------------------------------------------

data "terraform_remote_state" "network" {
  backend = "local"
  config = {
    path = "../../network/terraform.tfstate"
  }
}

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_subscription" "current" {}

data "azurerm_client_config" "current" {}
