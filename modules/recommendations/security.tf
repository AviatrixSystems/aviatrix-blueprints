# ─────────────────────────────────────────────────────────────────────────────
# Security Recommendations
#
# Defense-in-depth additions to complement Aviatrix DCF:
#   - Calico NetworkPolicy (in-cluster east-west segmentation)
#   - OPA Gatekeeper (policy-as-code admission control)
#   - External Secrets Operator (secrets management)
#   - Falco (runtime threat detection)
# ─────────────────────────────────────────────────────────────────────────────

#####################
# Calico — Kubernetes NetworkPolicy
#
# DCF operates at the network fabric layer (L3/L4 post-SNAT).
# Calico adds in-cluster NetworkPolicy enforcement as a fallback
# if DCF is misconfigured or briefly unavailable.
#
# Ref: https://docs.tigera.io/calico/latest/about/
# Analysis: Section 2 — "Add Kubernetes NetworkPolicy as defense-in-depth"
#####################

resource "helm_release" "calico" {
  count = var.enable_network_policy ? 1 : 0

  name             = "calico"
  repository       = "https://docs.tigera.io/calico/charts"
  chart            = "tigera-operator"
  version          = var.calico_chart_version
  namespace        = "tigera-operator"
  create_namespace = true

  # Use Calico in policy-only mode — VPC CNI handles pod networking
  set {
    name  = "installation.cni.type"
    value = "AmazonVPC"
  }

  set {
    name  = "installation.kubernetesProvider"
    value = "EKS"
  }

  wait    = true
  timeout = 600
}

#####################
# OPA Gatekeeper — Policy-as-Code
#
# Enforces admission policies beyond network rules:
#   - Container image allowlists
#   - Resource requests/limits requirements
#   - Label/annotation requirements
#   - Privilege escalation prevention
#
# Ref: https://open-policy-agent.github.io/gatekeeper/
# Analysis: Section 2 — "Add OPA/Gatekeeper or Kyverno"
#####################

resource "helm_release" "gatekeeper" {
  count = var.enable_gatekeeper ? 1 : 0

  name             = "gatekeeper"
  repository       = "https://open-policy-agent.github.io/gatekeeper/charts"
  chart            = "gatekeeper"
  version          = var.gatekeeper_chart_version
  namespace        = "gatekeeper-system"
  create_namespace = true

  set {
    name  = "replicas"
    value = "2"
  }

  set {
    name  = "audit.replicas"
    value = "1"
  }

  # Fail open during outages to avoid blocking all deployments
  set {
    name  = "controllerManager.webhook.failurePolicy"
    value = "Ignore"
  }

  wait    = true
  timeout = 300
}

#####################
# External Secrets Operator — Secrets Management
#
# Syncs secrets from AWS Secrets Manager / SSM Parameter Store
# into Kubernetes Secrets. Eliminates base64-encoded secrets in etcd.
#
# Ref: https://external-secrets.io/
# Analysis: Section 2 — "Secrets management"
#####################

resource "helm_release" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_secrets[0].arn
  }

  set {
    name  = "serviceAccount.name"
    value = "external-secrets"
  }

  wait    = true
  timeout = 300
}

#####################
# Falco — Runtime Threat Detection
#
# Monitors syscalls and container behavior for:
#   - Unexpected process execution
#   - File integrity changes
#   - Network anomalies
#   - Container drift detection
#
# Ref: https://falco.org/
# Analysis: Section 2 — "Runtime security"
#####################

resource "helm_release" "falco" {
  count = var.enable_falco ? 1 : 0

  name             = "falco"
  repository       = "https://falcosecurity.github.io/charts"
  chart            = "falco"
  version          = var.falco_chart_version
  namespace        = "falco"
  create_namespace = true

  # Use eBPF driver (no kernel module needed on managed EKS)
  set {
    name  = "driver.kind"
    value = "ebpf"
  }

  set {
    name  = "falcosidekick.enabled"
    value = "true"
  }

  wait    = true
  timeout = 300
}
