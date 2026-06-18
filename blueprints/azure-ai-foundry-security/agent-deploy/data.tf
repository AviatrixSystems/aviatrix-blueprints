data "terraform_remote_state" "foundry" {
  backend = "local"
  config = {
    path = "${path.module}/../foundry-playground/terraform.tfstate"
  }
}
