terraform {
  required_version = ">= 1.5"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# The Helm and Kubernetes providers talk to the ALREADY-DEPLOYED,
# Aviatrix-protected cluster via your kubeconfig. This blueprint does not build
# the cluster — it installs a workload and a firewall policy onto an existing one.
provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

# AWS is used to create the Bedrock IRSA role and to look up the EKS cluster's
# OIDC issuer (when eks_cluster_name is set). The region MUST be the cluster's
# region (the EKS data source is region-scoped) — this is independent of
# bedrock_region. Empty aws_region falls back to AWS_REGION / shared config.
# When eks_cluster_name is empty, no AWS resources or data sources are evaluated.
provider "aws" {
  region = var.aws_region != "" ? var.aws_region : null
}
