data "terraform_remote_state" "foundry" {
  backend = "local"
  config = {
    path = "../foundry-playground/terraform.tfstate"
  }
}
