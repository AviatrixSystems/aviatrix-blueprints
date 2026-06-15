terraform {
  required_version = ">= 1.5"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}

# The Helm provider talks to the ALREADY-DEPLOYED, Aviatrix-protected cluster
# via your kubeconfig. No cloud provider is configured here — this blueprint
# does not create infrastructure, it only installs a chart onto an existing
# cluster.
provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}
