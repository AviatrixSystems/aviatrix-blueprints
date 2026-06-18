data "terraform_remote_state" "network" {
  backend = "local"
  config = {
    path = "${path.module}/../network-infra/terraform.tfstate"
  }
}

data "azurerm_location" "current" {
  location = data.terraform_remote_state.network.outputs.location
}
