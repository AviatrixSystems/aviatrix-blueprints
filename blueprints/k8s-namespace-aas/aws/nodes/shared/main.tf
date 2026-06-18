#####################
# Pattern B: Namespace-as-a-Service — AWS Node Layer (Layer 3)
#
# Provisions:
#   - EKS managed node group for the shared cluster
#   - ENIConfig resources for VPC CNI custom networking (pod subnets)
#   - Aviatrix k8s-firewall Helm chart (CRDs for in-cluster DCF policies)
#   - ALB Controller + ExternalDNS via helm.tf
#
# This layer runs AFTER:
#   - Layer 1 (network/) — VPC, Aviatrix transit/spoke, Route53
#   - Layer 2 (clusters/) — EKS control plane, IRSA setup
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

provider "aws" {
  region = data.terraform_remote_state.network.outputs.aws_region
}

provider "aviatrix" {
  skip_version_validation = true
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", data.terraform_remote_state.cluster.outputs.cluster_name,
      "--region", data.terraform_remote_state.network.outputs.aws_region,
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", data.terraform_remote_state.cluster.outputs.cluster_name,
        "--region", data.terraform_remote_state.network.outputs.aws_region,
      ]
    }
  }
}

#####################
# Aviatrix Kubernetes Cluster Onboarding
# Registers the EKS cluster with the Aviatrix controller so DCF can
# inventory namespaces and enforce FirewallPolicy CRDs.
#####################

resource "aviatrix_kubernetes_cluster" "this" {
  cluster_id          = data.terraform_remote_state.cluster.outputs.cluster_arn
  use_csp_credentials = true
}

#####################
# Aviatrix k8s-firewall (CRDs)
#
# Installs FirewallPolicy and WebGroupPolicy CRDs for in-cluster DCF controls.
# These enable namespace-level and pod-label-level policies applied via kubectl.
# CRD-managed policies fill priority 70-99 (team self-service).
#####################

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
#
# Single node group for the shared cluster. All team namespaces
# schedule pods onto these nodes. Node-level isolation is NOT the
# goal — DCF provides the network isolation boundary.
#####################

resource "aws_eks_node_group" "shared" {
  cluster_name    = data.terraform_remote_state.cluster.outputs.cluster_name
  node_group_name = "shared-default"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = data.terraform_remote_state.network.outputs.shared_private_subnets

  scaling_config {
    min_size     = var.node_group_config.min_size
    max_size     = var.node_group_config.max_size
    desired_size = var.node_group_config.desired_size
  }

  instance_types = [var.node_group_config.instance_type]
  capacity_type  = var.node_group_config.capacity_type

  labels = {
    "nodepool-type" = "shared"
    "pattern"       = "namespace-aas"
  }

  tags = {
    Environment = "prod"
    Pattern     = "namespace-aas"
    Terraform   = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly,
    kubernetes_manifest.eniconfig,
  ]
}

#####################
# Node Group IAM Role
#####################

resource "aws_iam_role" "node_group" {
  name = "${data.terraform_remote_state.network.outputs.name_prefix}-shared-node-role"

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
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
}

#####################
# ENIConfig for VPC CNI Custom Networking
#
# Maps each AZ to its pod subnet so VPC CNI assigns pod IPs
# from the secondary CIDR (100.64.0.0/16) instead of the primary VPC CIDR.
#####################

resource "kubernetes_manifest" "eniconfig" {
  count = length(data.terraform_remote_state.network.outputs.shared_pod_subnet_ids)

  manifest = {
    apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
    kind       = "ENIConfig"
    metadata = {
      name = data.terraform_remote_state.network.outputs.shared_pod_subnet_azs[count.index]
    }
    spec = {
      subnet = data.terraform_remote_state.network.outputs.shared_pod_subnet_ids[count.index]
    }
  }
}
