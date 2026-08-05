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
  version    = var.k8s_firewall_chart_version
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
  source = "../../../../modules/aws-eks-node-group"

  # Cluster identity - from cluster state (exists at plan time)
  cluster_name    = data.terraform_remote_state.cluster.outputs.cluster_name
  cluster_version = data.terraform_remote_state.cluster.outputs.cluster_version

  # Network - from network state (exists at plan time)
  subnet_ids = data.terraform_remote_state.network.outputs.frontend_infra_private_subnet_ids

  # Security - from cluster state (exists at plan time)
  cluster_primary_security_group_id = data.terraform_remote_state.cluster.outputs.cluster_primary_security_group_id

  # Cluster service CIDR - read from cluster state
  cluster_service_cidr = data.terraform_remote_state.cluster.outputs.cluster_service_cidr

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

#####################
# EBS CSI Driver Addon + default StorageClass
#####################

# EKS 1.34 ships NO in-tree kubernetes.io/aws-ebs provisioner, so the
# auto-created `gp2` StorageClass is non-functional and is not marked default.
# Install the managed aws-ebs-csi-driver addon (provisioner ebs.csi.aws.com)
# so PVC-backed workloads can provision block storage. IRSA role comes from the
# cluster layer. Deployed here (Layer 3) because controller/node pods need nodes.
resource "aws_eks_addon" "aws_ebs_csi_driver" {
  cluster_name             = data.terraform_remote_state.cluster.outputs.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = data.terraform_remote_state.cluster.outputs.ebs_csi_role_arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  preserve = true

  tags = {
    Environment = "demo"
    Cluster     = "frontend"
    Terraform   = "true"
  }

  depends_on = [module.default_node_group]
}

# Default StorageClass backed by the EBS CSI driver (gp3).
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    fsType    = "ext4"
    encrypted = "true"
  }

  depends_on = [aws_eks_addon.aws_ebs_csi_driver]
}
