# Data source to read network outputs
data "terraform_remote_state" "network" {
  backend = "local"

  config = {
    path = "../../network/terraform.tfstate"
  }
}

# Data source to read cluster outputs
# This is the key to solving the chicken-and-egg problem:
# By the time this runs, the cluster state exists and all values are known
data "terraform_remote_state" "cluster" {
  backend = "local"

  config = {
    path = "../../clusters/backend/terraform.tfstate"
  }
}
