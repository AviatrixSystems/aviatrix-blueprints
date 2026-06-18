# -----------------------------------------------------------------------------
# Pattern C: EKS Production Cluster — Data Sources
# Read network layer outputs via remote state
# -----------------------------------------------------------------------------

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
