terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Query the EKS cluster to get its current version
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

# EKS Managed Node Group
# This module is deployed AFTER the cluster exists, solving the chicken-and-egg problem
module "node_group" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "~> 21.9"

  name               = "${var.cluster_name}-${var.node_group_name}"
  cluster_name       = var.cluster_name
  kubernetes_version = var.cluster_version

  # Cluster service CIDR - required for user data
  cluster_service_cidr = var.cluster_service_cidr

  # Subnet IDs - these come from network state (static at plan time)
  subnet_ids = var.subnet_ids

  # Scaling configuration
  min_size     = var.min_size
  max_size     = var.max_size
  desired_size = var.desired_size

  # Instance configuration
  instance_types = var.instance_types
  capacity_type  = var.capacity_type
  ami_type       = var.ami_type

  # Security - these values come from cluster state (which exists at plan time)
  cluster_primary_security_group_id = var.cluster_primary_security_group_id

  # IAM - let the module create the role
  create_iam_role = true
  iam_role_name   = "${var.cluster_name}-${var.node_group_name}-role"
  iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # Labels and taints
  labels = var.labels
  taints = {} # Taints disabled - use var.taints if needed (must be map format)

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-${var.node_group_name}"
  })
}
