data "terraform_remote_state" "network" {
  backend = "local"
  config = {
    path = "../../network/terraform.tfstate"
  }
}

data "terraform_remote_state" "cluster" {
  backend = "local"
  config = {
    path = "../../clusters/backend/terraform.tfstate"
  }
}

data "azurerm_client_config" "current" {}
