data "terraform_remote_state" "network" {
  backend = "local"
  config = {
    path = "../network-infra/terraform.tfstate"
  }
}

data "azurerm_location" "current" {
  location = data.terraform_remote_state.network.outputs.location
}
