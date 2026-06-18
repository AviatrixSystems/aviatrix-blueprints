# Data source to read network outputs
data "terraform_remote_state" "network" {
  backend = "local"

  config = {
    path = "../../network/terraform.tfstate"
  }
}

# Data source to read cluster outputs
data "terraform_remote_state" "cluster" {
  backend = "local"

  config = {
    path = "../../clusters/team-a/terraform.tfstate"
  }
}
