#####################
# Platform DCF Baseline — In-Cluster Enforcement
#
# Complements the transit-level DCF ruleset (network/dcf.tf) by enforcing
# the same isolation rules for intra-cluster pod-to-pod traffic that never
# traverses the Aviatrix spoke gateway.
#
# Two mechanisms:
#   1. Aviatrix FirewallPolicy CRDs — enforced by the k8s-firewall controller
#      (installed via helm_release.k8s_firewall). References DCF SmartGroups
#      by name so rules stay aligned with the transit-level policy.
#
#   2. Kubernetes NetworkPolicy — Calico ingress-only rules as a second layer.
#      Egress is NOT restricted here; DCF handles egress at the gateway.
#
# Both depend on the k8s-firewall Helm release being ready first.
#####################

locals {
  name_prefix = data.terraform_remote_state.network.outputs.name_prefix
}

#####################
# Aviatrix FirewallPolicy CRDs
#
# Priority layout matches the platform DCF baseline (network/dcf.tf):
#   priority 10: PERMIT team-a -> team-b TCP/443
#   priority 50: DENY   team-a <-> team-c
#   priority 52: DENY   team-b <-> team-c
#####################

resource "kubernetes_manifest" "firewall_policy_team_a" {
  manifest = {
    apiVersion = "networking.aviatrix.com/v1alpha1"
    kind       = "FirewallPolicy"
    metadata = {
      name      = "namespace-isolation"
      namespace = "team-a"
    }
    spec = {
      rules = [
        {
          name     = "permit-to-team-b-api"
          action   = "permit"
          protocol = "tcp"
          port     = 443
          logging  = true
          destinationSmartGroups = [
            { name = "${local.name_prefix}-team-b-ns" }
          ]
        },
        {
          name     = "deny-to-team-c"
          action   = "deny"
          protocol = "any"
          logging  = true
          destinationSmartGroups = [
            { name = "${local.name_prefix}-team-c-ns" }
          ]
        }
      ]
    }
  }

  depends_on = [
    helm_release.k8s_firewall,
    kubernetes_namespace.team_a,
  ]
}

resource "kubernetes_manifest" "firewall_policy_team_b" {
  manifest = {
    apiVersion = "networking.aviatrix.com/v1alpha1"
    kind       = "FirewallPolicy"
    metadata = {
      name      = "namespace-isolation"
      namespace = "team-b"
    }
    spec = {
      rules = [
        {
          name     = "deny-to-team-c"
          action   = "deny"
          protocol = "any"
          logging  = true
          destinationSmartGroups = [
            { name = "${local.name_prefix}-team-c-ns" }
          ]
        }
      ]
    }
  }

  depends_on = [
    helm_release.k8s_firewall,
    kubernetes_namespace.team_b,
  ]
}

resource "kubernetes_manifest" "firewall_policy_team_c" {
  manifest = {
    apiVersion = "networking.aviatrix.com/v1alpha1"
    kind       = "FirewallPolicy"
    metadata = {
      name      = "namespace-isolation"
      namespace = "team-c"
    }
    spec = {
      rules = [
        {
          name     = "deny-to-team-a"
          action   = "deny"
          protocol = "any"
          logging  = true
          destinationSmartGroups = [
            { name = "${local.name_prefix}-team-a-ns" }
          ]
        },
        {
          name     = "deny-to-team-b"
          action   = "deny"
          protocol = "any"
          logging  = true
          destinationSmartGroups = [
            { name = "${local.name_prefix}-team-b-ns" }
          ]
        }
      ]
    }
  }

  depends_on = [
    helm_release.k8s_firewall,
    kubernetes_namespace.team_c,
  ]
}

#####################
# Kubernetes NetworkPolicy (Calico — ingress only)
#
# Second enforcement layer for intra-node traffic.
# Mirrors the DCF rules at the Kubernetes API level.
#####################

resource "kubernetes_network_policy" "team_a_isolation" {
  metadata {
    name      = "namespace-isolation"
    namespace = kubernetes_namespace.team_a.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {}
      }
    }
  }
}

resource "kubernetes_network_policy" "team_b_isolation" {
  metadata {
    name      = "namespace-isolation"
    namespace = kubernetes_namespace.team_b.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {}
      }
    }
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "team-a"
          }
        }
      }
    }
  }
}

resource "kubernetes_network_policy" "team_c_isolation" {
  metadata {
    name      = "namespace-isolation"
    namespace = kubernetes_namespace.team_c.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {}
      }
    }
  }
}
