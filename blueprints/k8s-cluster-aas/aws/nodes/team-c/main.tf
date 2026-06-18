#####################
# EKS Node Layer (Layer 3) - Team-C
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
# Aviatrix Kubernetes Cluster Onboarding
#####################

resource "aviatrix_kubernetes_cluster" "this" {
  cluster_id          = data.terraform_remote_state.cluster.outputs.cluster_arn
  use_csp_credentials = true
}

#####################
# Aviatrix k8s-firewall (CRDs)
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
#####################

resource "aws_eks_node_group" "default" {
  cluster_name    = data.terraform_remote_state.cluster.outputs.cluster_name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = data.terraform_remote_state.network.outputs.team_c_private_subnet_ids

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
    "team"          = "team-c"
  }

  tags = {
    Environment = "demo"
    Team        = "team-c"
    Terraform   = "true"
  }
}

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
    Team        = "team-c"
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
#####################

resource "kubernetes_manifest" "eniconfig_a" {
  manifest = {
    apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
    kind       = "ENIConfig"
    metadata = {
      name = "${data.terraform_remote_state.network.outputs.aws_region}a"
    }
    spec = {
      subnet = data.terraform_remote_state.network.outputs.team_c_pod_subnet_ids[0]
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
      subnet = data.terraform_remote_state.network.outputs.team_c_pod_subnet_ids[1]
    }
  }

}
