terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Kubernetes provider for ENIConfig resources
# By Layer 3, the cluster exists and can authenticate
provider "kubernetes" {
  host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.cluster.outputs.cluster_name, "--region", var.aws_region]
  }
}

# Helm provider for Kubernetes add-ons
# Uses the same authentication as the Kubernetes provider
provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.cluster.outputs.cluster_name, "--region", var.aws_region]
    }
  }
}

#####################
# Aviatrix Distributed Cloud Firewall (DCF) for Kubernetes
#####################

# Install the k8s-firewall Helm chart which provides CRDs for:
# - firewallpolicies.networking.aviatrix.com
# - webgrouppolicies.networking.aviatrix.com
# These enable Kubernetes-native firewall policy management via Aviatrix DCF
resource "helm_release" "k8s_firewall" {
  name       = "k8s-firewall"
  repository = "https://aviatrixsystems.github.io/k8s-firewall-charts"
  chart      = "k8s-firewall"
  namespace  = "default"

  # Skip waiting for resources - CRDs don't have traditional ready status
  wait = false

  # Recreate pods on upgrade to pick up new CRD versions
  recreate_pods = false
}

#####################
# ENIConfig for VPC CNI Custom Networking
#####################

# ENIConfig resources tell the VPC CNI which subnet and security group to use for pod ENIs
# Deployed in Layer 3 (after cluster exists) to avoid Kubernetes provider auth issues
resource "kubernetes_manifest" "eniconfig" {
  for_each = { for idx, az in data.terraform_remote_state.network.outputs.frontend_availability_zones : az => data.terraform_remote_state.network.outputs.frontend_pod_private_subnet_ids[idx] }

  manifest = {
    apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
    kind       = "ENIConfig"
    metadata = {
      name = each.key
    }
    spec = {
      subnet         = each.value
      securityGroups = [data.terraform_remote_state.cluster.outputs.pod_security_group_id]
    }
  }
}

#####################
# Frontend EKS Node Group
#####################

# This deployment runs AFTER frontend-cluster exists
# All values from the cluster state are known at plan time

module "default_node_group" {
  source = "../../modules/eks-node-group"

  # Cluster identity - from cluster state (exists at plan time)
  cluster_name    = data.terraform_remote_state.cluster.outputs.cluster_name
  cluster_version = data.terraform_remote_state.cluster.outputs.cluster_version

  # Network - from network state (exists at plan time)
  subnet_ids = data.terraform_remote_state.network.outputs.frontend_infra_private_subnet_ids

  # Security - from cluster state (exists at plan time)
  cluster_primary_security_group_id = data.terraform_remote_state.cluster.outputs.cluster_primary_security_group_id

  # Cluster service CIDR - use default EKS service CIDR
  cluster_service_cidr = "172.20.0.0/16"

  # Scaling configuration - from variables (known at plan time)
  node_group_name = "default"
  min_size        = var.node_group_config.min_size
  max_size        = var.node_group_config.max_size
  desired_size    = var.node_group_config.desired_size

  # Instance configuration - from variables (known at plan time)
  instance_types = var.node_group_config.instance_types
  capacity_type  = var.node_group_config.capacity_type

  tags = {
    Environment = "demo"
    Cluster     = "frontend"
    Terraform   = "true"
  }

  # Ensure ENIConfig is created before nodes so pods get correct networking
  depends_on = [kubernetes_manifest.eniconfig]
}

#####################
# CoreDNS Addon
#####################

# Deploy CoreDNS in Layer 3 after nodes exist
# This ensures CoreDNS pods can be scheduled immediately
resource "aws_eks_addon" "coredns" {
  cluster_name = data.terraform_remote_state.cluster.outputs.cluster_name
  addon_name   = "coredns"

  # Omit addon_version to use latest compatible version
  resolve_conflicts_on_create = "NONE"
  resolve_conflicts_on_update = "OVERWRITE"

  preserve = true

  tags = {
    Environment = "demo"
    Cluster     = "frontend"
    Terraform   = "true"
  }

  # Ensure nodes are created before CoreDNS is deployed
  depends_on = [module.default_node_group]
}
