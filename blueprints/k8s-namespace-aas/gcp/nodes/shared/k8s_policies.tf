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
