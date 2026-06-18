#####################
# K8s-Typed SmartGroups
#
# Once the GKE clusters are onboarded with the Aviatrix Controller (via the
# clusters/{frontend,backend} layers), the controller resolves K8s-typed
# selectors dynamically: pod IPs are listed from the cluster API and added to
# the SmartGroup as members.
#
# Cluster IDs are constructed in main.tf locals (frontend_cluster_id,
# backend_cluster_id) and must match google_container_cluster.this.self_link
# in the clusters layer.
#
# Until the clusters are onboarded these SmartGroups have zero members and any
# DCF rules referencing them are no-ops — safe to deploy in either order.
#####################

#####################
# Cluster-scoped (analog of the VPC SmartGroup, but membership is pods+nodes
# resolved from the cluster API instead of from VPC/IP)
#####################

resource "aviatrix_smart_group" "frontend_cluster" {
  count = var.enable_k8s_smartgroup_demo ? 1 : 0
  name  = "${var.name_prefix}-sg-frontend-cluster"
  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = local.frontend_cluster_id
    }
  }
}

resource "aviatrix_smart_group" "backend_cluster" {
  count = var.enable_k8s_smartgroup_demo ? 1 : 0
  name  = "${var.name_prefix}-sg-backend-cluster"
  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = local.backend_cluster_id
    }
  }
}

#####################
# Namespace-scoped — Gatus pods only
#####################

resource "aviatrix_smart_group" "frontend_gatus_ns" {
  count = var.enable_k8s_smartgroup_demo ? 1 : 0
  name  = "${var.name_prefix}-sg-frontend-gatus-ns"
  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = local.frontend_cluster_id
      k8s_namespace  = "gatus"
    }
  }
}

resource "aviatrix_smart_group" "backend_gatus_ns" {
  count = var.enable_k8s_smartgroup_demo ? 1 : 0
  name  = "${var.name_prefix}-sg-backend-gatus-ns"
  selector {
    match_expressions {
      type           = "k8s"
      k8s_cluster_id = local.backend_cluster_id
      k8s_namespace  = "gatus"
    }
  }
}
