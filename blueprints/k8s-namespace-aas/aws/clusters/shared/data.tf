# Data source to read network outputs
data "terraform_remote_state" "network" {
  backend = "local"

  config = {
    path = "../../network/terraform.tfstate"
  }
}

# Aviatrix access account — used to get the controller's IAM role ARN
# for EKS access entry (K8s inventory: namespaces, pods, DCF CRDs)
data "aviatrix_account" "aws_account" {
  account_name = var.aviatrix_aws_account_name
}
