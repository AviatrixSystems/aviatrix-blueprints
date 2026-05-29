#####################
# Platform Namespaces + RBAC
#
# Creates team namespaces and shared infrastructure namespaces.
# Labels enable DCF SmartGroup matching (k8s_namespace field).
#
# RBAC restricts API access per team. DCF enforces network isolation.
# These are NOT the same boundary — DCF is the hard network control.
#####################

resource "kubernetes_namespace" "team_a" {
  metadata {
    name = "team-a"
    labels = {
      team    = "team-a"
      pattern = "namespace-aas"
    }
  }
}

resource "kubernetes_namespace" "team_b" {
  metadata {
    name = "team-b"
    labels = {
      team    = "team-b"
      pattern = "namespace-aas"
    }
  }
}

resource "kubernetes_namespace" "team_c" {
  metadata {
    name = "team-c"
    labels = {
      team    = "team-c"
      pattern = "namespace-aas"
    }
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      app     = "monitoring"
      pattern = "namespace-aas"
    }
  }
}

resource "kubernetes_namespace" "istio_system" {
  metadata {
    name = "istio-system"
    labels = {
      app     = "istio"
      pattern = "namespace-aas"
    }
  }
}

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
    labels = {
      app     = "cert-manager"
      pattern = "namespace-aas"
    }
  }
}

#####################
# RBAC — Team namespace admin bindings
# Restricts kubectl access per team. Network isolation is enforced by DCF.
#####################

resource "kubernetes_role_binding" "team_a_admin" {
  metadata {
    name      = "team-a-admin"
    namespace = kubernetes_namespace.team_a.metadata[0].name
  }
  subject {
    kind      = "Group"
    name      = "team-a-developers"
    api_group = "rbac.authorization.k8s.io"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }
}

resource "kubernetes_role_binding" "team_b_admin" {
  metadata {
    name      = "team-b-admin"
    namespace = kubernetes_namespace.team_b.metadata[0].name
  }
  subject {
    kind      = "Group"
    name      = "team-b-developers"
    api_group = "rbac.authorization.k8s.io"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }
}

resource "kubernetes_role_binding" "team_c_admin" {
  metadata {
    name      = "team-c-admin"
    namespace = kubernetes_namespace.team_c.metadata[0].name
  }
  subject {
    kind      = "Group"
    name      = "team-c-developers"
    api_group = "rbac.authorization.k8s.io"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }
}
