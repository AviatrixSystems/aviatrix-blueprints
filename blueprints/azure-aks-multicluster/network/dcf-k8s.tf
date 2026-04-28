#####################
# K8s-Typed SmartGroups
#
# Once the AKS clusters are onboarded with the Aviatrix Controller (via the
# clusters/{frontend,backend} layers), the controller resolves K8s-typed
# selectors dynamically: pod IPs are listed from the cluster API and added
# to the SmartGroup as members.
#
# Cluster IDs are constructed here (not read from the clusters layer) because
# the network layer is applied first. The construction must match the format
# produced by lower(azurerm_kubernetes_cluster.aks.id) in the clusters layer:
#   /subscriptions/{sub}/resourcegroups/{rg}/providers/microsoft.containerservice/managedclusters/{name}
#
# Until the clusters are onboarded these SmartGroups have zero members and
# any DCF rules referencing them are no-ops — safe to deploy in either order.
#####################

data "azurerm_client_config" "current" {}

locals {
  subscription_id = data.azurerm_client_config.current.subscription_id

  # Must match lower(azurerm_kubernetes_cluster.aks.id) in clusters/* layers.
  frontend_aks_cluster_id = lower("/subscriptions/${local.subscription_id}/resourcegroups/${var.name_prefix}-frontend-rg/providers/microsoft.containerservice/managedclusters/${var.name_prefix}-frontend")
  backend_aks_cluster_id  = lower("/subscriptions/${local.subscription_id}/resourcegroups/${var.name_prefix}-backend-rg/providers/microsoft.containerservice/managedclusters/${var.name_prefix}-backend")
}

#####################
# Cluster-scoped (analog of the VNet SmartGroup, but membership is pods+nodes
# resolved from the cluster API instead of from VNet/IP)
#####################

resource "aviatrix_smart_group" "frontend_cluster" {
  name = "${var.name_prefix}-sg-frontend-cluster"
  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = local.frontend_aks_cluster_id
    }
  }
}

resource "aviatrix_smart_group" "backend_cluster" {
  name = "${var.name_prefix}-sg-backend-cluster"
  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = local.backend_aks_cluster_id
    }
  }
}

#####################
# Namespace-scoped — Gatus pods only
# Demonstrates finer-grained policy than VNet selectors allow.
#####################

resource "aviatrix_smart_group" "frontend_gatus_ns" {
  name = "${var.name_prefix}-sg-frontend-gatus-ns"
  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = local.frontend_aks_cluster_id
      k8s_namespace  = "gatus"
    }
  }
}

resource "aviatrix_smart_group" "backend_gatus_ns" {
  name = "${var.name_prefix}-sg-backend-gatus-ns"
  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = local.backend_aks_cluster_id
      k8s_namespace  = "gatus"
    }
  }
}

#####################
# Outputs (referenced by clusters/* docs and validation)
#####################

output "frontend_aks_cluster_id" {
  description = "Constructed AKS cluster_id used as the K8s SmartGroup selector value (matches what clusters/frontend onboards)"
  value       = local.frontend_aks_cluster_id
}

output "backend_aks_cluster_id" {
  description = "Constructed AKS cluster_id used as the K8s SmartGroup selector value (matches what clusters/backend onboards)"
  value       = local.backend_aks_cluster_id
}

output "smartgroup_frontend_gatus_ns_uuid" {
  description = "UUID of the K8s namespace SmartGroup for the frontend gatus namespace"
  value       = aviatrix_smart_group.frontend_gatus_ns.uuid
}

output "smartgroup_backend_gatus_ns_uuid" {
  description = "UUID of the K8s namespace SmartGroup for the backend gatus namespace"
  value       = aviatrix_smart_group.backend_gatus_ns.uuid
}
