# Pattern C: EKS Non-Production Nodes

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    helm       = { source = "hashicorp/helm", version = "~> 2.12" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.25" }
    aviatrix   = { source = "AviatrixSystems/aviatrix", version = "~> 8.2.0" }
  }
}

locals {
  cluster_name     = data.terraform_remote_state.cluster.outputs.cluster_name
  cluster_endpoint = data.terraform_remote_state.cluster.outputs.cluster_endpoint
  cluster_ca       = data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data
  region           = "us-east-2"
}

provider "aws" { region = local.region }

provider "aviatrix" {
  skip_version_validation = true
}

provider "helm" {
  kubernetes {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca)
  token                  = data.aws_eks_cluster_auth.this.token
}

# Aviatrix Kubernetes Cluster Onboarding
# Registers the EKS cluster with the Aviatrix controller so DCF can
# inventory namespaces and enforce FirewallPolicy CRDs.
resource "aviatrix_kubernetes_cluster" "this" {
  cluster_id          = data.terraform_remote_state.cluster.outputs.cluster_arn
  use_csp_credentials = true
}

resource "helm_release" "k8s_firewall" {
  name             = "k8s-firewall"
  namespace        = "aviatrix-system"
  create_namespace = true
  repository       = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart            = "k8s-firewall"

  set {
    name  = "cloud"
    value = "AWS"
  }
}
