data "terraform_remote_state" "network" {
  backend = "local"
  config  = { path = "../../network/terraform.tfstate" }
}

data "terraform_remote_state" "cluster" {
  backend = "local"
  config  = { path = "../../clusters/prod/terraform.tfstate" }
}

data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.cluster.outputs.cluster_name
}
