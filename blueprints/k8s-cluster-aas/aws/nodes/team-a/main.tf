#####################
# EKS Node Layer (Layer 3) - Team-A
#
# Provisions:
#   - EKS managed node group
#   - ENIConfig resources for VPC CNI custom networking
#   - Aviatrix k8s-firewall Helm chart (CRDs for in-cluster DCF policies)
#   - ALB Controller + ExternalDNS (via helm.tf)
#
# This layer runs AFTER:
#   - Layer 1 (network/) - VPCs, Aviatrix transit/spoke, Route53
#   - Layer 2 (clusters/) - EKS control plane, IRSA roles
#####################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2.0"
    }
  }
}

provider "aviatrix" {
  skip_version_validation = true
}

provider "aws" {
  region = data.terraform_remote_state.network.outputs.aws_region
}

data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.cluster.outputs.cluster_name
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

#####################
# Aviatrix k8s-firewall (CRDs)
#
# Installs FirewallPolicy and WebGroupPolicy CRDs for in-cluster DCF controls.
# These enable namespace-level and pod-label-level policies applied via kubectl.
# NOTE: CRDs are optional in Pattern A but available if teams want them.
#####################

#####################
# Aviatrix Kubernetes Cluster Onboarding
# Registers the EKS cluster with the Aviatrix controller so DCF can
# inventory namespaces and enforce FirewallPolicy CRDs.
#####################

resource "aviatrix_kubernetes_cluster" "this" {
  cluster_id          = data.terraform_remote_state.cluster.outputs.cluster_arn
  use_csp_credentials = true
}

resource "helm_release" "k8s_firewall" {
  name             = "k8s-firewall"
  repository       = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart            = "k8s-firewall"
  namespace        = "aviatrix-system"
  create_namespace = true

  set {
    name  = "cloud"
    value = "AWS"
  }
}

#####################
# EKS Managed Node Group
#####################

resource "aws_eks_node_group" "default" {
  cluster_name    = data.terraform_remote_state.cluster.outputs.cluster_name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = data.terraform_remote_state.network.outputs.team_a_private_subnet_ids

  depends_on = [kubernetes_manifest.eniconfig_a, kubernetes_manifest.eniconfig_b]

  scaling_config {
    min_size     = var.node_group_config.min_size
    max_size     = var.node_group_config.max_size
    desired_size = var.node_group_config.desired_size
  }

  instance_types = [var.node_group_config.instance_type]
  capacity_type  = var.node_group_config.capacity_type

  labels = {
    "nodepool-type" = "user"
    "team"          = "team-a"
  }

  tags = {
    Environment = "demo"
    Team        = "team-a"
    Terraform   = "true"
  }
}

# IAM role for EKS node group
resource "aws_iam_role" "node_group" {
  name = "${data.terraform_remote_state.cluster.outputs.cluster_name}-node-group"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Environment = "demo"
    Team        = "team-a"
    Terraform   = "true"
  }
}

resource "aws_iam_role_policy_attachment" "node_group_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
}

#####################
# ENIConfig for VPC CNI Custom Networking
#
# Maps each AZ to a pod subnet in the secondary CIDR (100.64.0.0/16).
# This is the AWS-specific mechanism for separating pod IPs from node IPs.
# Azure and GCP handle this natively (CNI Overlay / alias IPs).
#####################

resource "kubernetes_manifest" "eniconfig_a" {
  manifest = {
    apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
    kind       = "ENIConfig"
    metadata = {
      name = "${data.terraform_remote_state.network.outputs.aws_region}a"
    }
    spec = {
      subnet = data.terraform_remote_state.network.outputs.team_a_pod_subnet_ids[0]
    }
  }

}

resource "kubernetes_manifest" "eniconfig_b" {
  manifest = {
    apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
    kind       = "ENIConfig"
    metadata = {
      name = "${data.terraform_remote_state.network.outputs.aws_region}b"
    }
    spec = {
      subnet = data.terraform_remote_state.network.outputs.team_a_pod_subnet_ids[1]
    }
  }

}
