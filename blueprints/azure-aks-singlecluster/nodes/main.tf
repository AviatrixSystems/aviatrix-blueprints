locals {
  net     = data.terraform_remote_state.network.outputs
  cluster = data.terraform_remote_state.cluster.outputs
}

provider "kubernetes" {
  host                   = local.cluster.host
  client_certificate     = base64decode(local.cluster.client_certificate)
  client_key             = base64decode(local.cluster.client_key)
  cluster_ca_certificate = base64decode(local.cluster.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = local.cluster.host
    client_certificate     = base64decode(local.cluster.client_certificate)
    client_key             = base64decode(local.cluster.client_key)
    cluster_ca_certificate = base64decode(local.cluster.cluster_ca_certificate)
  }
}
