#####################
# Non-Production Namespaces
#
# Creates team and shared namespaces in the non-production AKS cluster.
# Sandbox has relaxed egress (controlled by sandbox_relaxed_egress WebGroup
# in network/dcf.tf) but has NO path to production data — enforced at Layer 1
# (VNet SmartGroups deny nonprod-vnet -> prod-vnet in all directions).
#####################

resource "kubernetes_namespace" "team_a_dev" {
  metadata {
    name = "team-a-dev"
    labels = {
      environment            = "development"
      team                   = "team-a"
      "aviatrix.io/enforced" = "true"
    }
  }
}

resource "kubernetes_namespace" "team_b_staging" {
  metadata {
    name = "team-b-staging"
    labels = {
      environment            = "staging"
      team                   = "team-b"
      "aviatrix.io/enforced" = "true"
    }
  }
}

resource "kubernetes_namespace" "sandbox" {
  metadata {
    name = "sandbox"
    labels = {
      environment            = "sandbox"
      purpose                = "experimentation"
      "aviatrix.io/enforced" = "true"
      "egress-policy"        = "relaxed"
    }
  }
}

resource "kubernetes_namespace" "monitoring_nonprod" {
  metadata {
    name = "monitoring"
    labels = {
      environment            = "non-production"
      purpose                = "observability"
      "aviatrix.io/enforced" = "true"
    }
  }
}
