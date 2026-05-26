data "terraform_remote_state" "network" {
  backend = "local"
  config = {
    path = "${path.module}/../network-infra/terraform.tfstate"
  }
}
