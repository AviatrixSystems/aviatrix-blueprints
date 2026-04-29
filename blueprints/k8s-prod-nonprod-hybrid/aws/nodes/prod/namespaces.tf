#####################
# Production Namespaces
#
# Creates team and shared namespaces in the production EKS cluster.
# Labels enable DCF SmartGroup matching (k8s_cluster_id + k8s_namespace).
# aviatrix.io/enforced: "true" signals the k8s-firewall controller to
# apply CRD-managed FirewallPolicies in this namespace.
#####################

resource "kubernetes_namespace" "team_a_prod" {
  metadata {
    name = "team-a-prod"
    labels = {
      environment            = "production"
      team                   = "team-a"
      "aviatrix.io/enforced" = "true"
    }
  }
}

resource "kubernetes_namespace" "team_b_prod" {
  metadata {
    name = "team-b-prod"
    labels = {
      environment            = "production"
      team                   = "team-b"
      "aviatrix.io/enforced" = "true"
    }
  }
}

resource "kubernetes_namespace" "monitoring_prod" {
  metadata {
    name = "monitoring"
    labels = {
      environment            = "production"
      purpose                = "observability"
      "aviatrix.io/enforced" = "true"
    }
  }
}
