# Conductor for the secure-enterprise-chat blueprint.
#
# One `terraform apply` installs the OFFICIAL LibreChat chart onto an existing,
# Aviatrix-protected cluster and:
#   1. generates the app secrets and writes the credentials Secret,
#   2. creates the Bedrock IRSA role from the cluster OIDC issuer (EKS only),
#   3. auto-detects the ingress class,
#   4. generates and applies the egress FirewallPolicy CRD.
#
# It references the SAME standalone files under chart/ and egress-policy/ that
# raw `helm` and ArgoCD use — delete this Terraform and you can still deploy by
# hand. See README.md ("À la carte").

locals {
  irsa = var.eks_cluster_name != ""

  # --- Ingress auto-detection ---
  # Names of the IngressClass objects present on the target cluster.
  ingress_class_names = try(
    [for o in data.kubernetes_resources.ingress_classes.objects : o.metadata.name],
    []
  )
  # Explicit override wins; otherwise prefer alb (EKS / AWS LB Controller) then
  # nginx (AKS / ingress-nginx). Empty string => install with ingress disabled.
  detected_ingress_class = (
    var.ingress_class_name != "" ? var.ingress_class_name :
    contains(local.ingress_class_names, "alb") ? "alb" :
    contains(local.ingress_class_names, "nginx") ? "nginx" :
    ""
  )
  ingress_enabled = local.detected_ingress_class != ""

  # --- IRSA / OIDC ---
  oidc_issuer = local.irsa ? data.aws_eks_cluster.this[0].identity[0].oidc[0].issuer : ""
  oidc_host   = replace(local.oidc_issuer, "https://", "")
  oidc_arn    = local.irsa ? "arn:aws:iam::${data.aws_caller_identity.current[0].account_id}:oidc-provider/${local.oidc_host}" : ""
  role_arn    = local.irsa ? aws_iam_role.bedrock[0].arn : ""

  # kubectl flags so the generator-applied CRD targets the same cluster as the
  # providers (used by the null_resource provisioners below).
  kubectl_context_flag = var.kube_context != "" ? "--context ${var.kube_context}" : ""

  values_overlay = file("${path.module}/chart/values.yaml")

  # Inject the standalone librechat.yaml as configYamlContent (equivalent to
  # `helm --set-file librechat.configYamlContent=chart/librechat.yaml`).
  config_overlay = yamlencode({
    librechat = {
      configYamlContent = file("${path.module}/chart/librechat.yaml")
    }
  })
}

# --- Cluster discovery: ingress classes -------------------------------------
data "kubernetes_resources" "ingress_classes" {
  api_version = "networking.k8s.io/v1"
  kind        = "IngressClass"
}

# --- Namespace --------------------------------------------------------------
resource "kubernetes_namespace" "this" {
  metadata {
    name = var.namespace
  }
}

# --- Generated secrets ------------------------------------------------------
# CREDS_KEY / CREDS_IV must be hex (LibreChat: 32-byte key, 16-byte IV).
resource "random_id" "creds_key" {
  byte_length = 32
}

resource "random_id" "creds_iv" {
  byte_length = 16
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "random_password" "jwt_refresh" {
  length  = 64
  special = false
}

resource "random_password" "meili_master_key" {
  length  = 48
  special = false
}

# The chart consumes this via librechat.existingSecretName and
# meilisearch.auth.existingMasterKeySecret. No static AWS keys: Bedrock auth is
# IRSA (the SA annotation below), resolved through the AWS default provider chain.
resource "kubernetes_secret" "credentials" {
  metadata {
    name      = "librechat-credentials-env"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  data = {
    CREDS_KEY          = random_id.creds_key.hex
    CREDS_IV           = random_id.creds_iv.hex
    JWT_SECRET         = random_password.jwt_secret.result
    JWT_REFRESH_SECRET = random_password.jwt_refresh.result
    MEILI_MASTER_KEY   = random_password.meili_master_key.result

    # Without these LibreChat hides the Sign Up button (treated as disabled when
    # unset). Set ALLOW_REGISTRATION=false once your first admin account exists.
    ALLOW_EMAIL_LOGIN  = "true"
    ALLOW_REGISTRATION = "true"

    # Bedrock: region is always required; models drive the UI dropdown.
    BEDROCK_AWS_DEFAULT_REGION = var.bedrock_region
    BEDROCK_AWS_MODELS         = var.bedrock_models
  }

  type = "Opaque"
}

# --- Bedrock IRSA role (EKS only) -------------------------------------------
data "aws_caller_identity" "current" {
  count = local.irsa ? 1 : 0
}

data "aws_eks_cluster" "this" {
  count = local.irsa ? 1 : 0
  name  = var.eks_cluster_name
}

data "aws_iam_policy_document" "assume" {
  count = local.irsa ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.release_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "bedrock" {
  count = local.irsa ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    # Both the cross-region inference profile (account-scoped) and the underlying
    # Anthropic foundation models (account-less ARN) — InvokeModel touches both.
    resources = [
      "arn:aws:bedrock:*:${data.aws_caller_identity.current[0].account_id}:inference-profile/*",
      "arn:aws:bedrock:*::foundation-model/anthropic.*",
    ]
  }
}

resource "aws_iam_role" "bedrock" {
  count              = local.irsa ? 1 : 0
  name               = "${var.release_name}-bedrock-${var.eks_cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.assume[0].json

  tags = {
    Blueprint = "secure-enterprise-chat"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy" "bedrock" {
  count  = local.irsa ? 1 : 0
  name   = "bedrock-invoke"
  role   = aws_iam_role.bedrock[0].id
  policy = data.aws_iam_policy_document.bedrock[0].json
}

# --- LibreChat Helm release -------------------------------------------------
resource "helm_release" "librechat" {
  name             = var.release_name
  chart            = "oci://ghcr.io/danny-avila/librechat-chart/librechat"
  version          = var.chart_version
  namespace        = kubernetes_namespace.this.metadata[0].name
  create_namespace = false

  # Later entries win, so config_overlay's configYamlContent takes precedence.
  values = [
    local.values_overlay,
    local.config_overlay,
  ]

  # Auto-detected ingress.
  set {
    name  = "ingress.enabled"
    value = tostring(local.ingress_enabled)
  }

  dynamic "set" {
    for_each = local.ingress_enabled ? [1] : []
    content {
      name  = "ingress.className"
      value = local.detected_ingress_class
    }
  }

  # Host-less by default; a real host only when ingress_host is set.
  set {
    name  = "ingress.hosts[0].host"
    value = var.ingress_host
  }

  # On EKS the AWS Load Balancer Controller defaults to an INTERNAL ALB with no
  # annotations, which would be unreachable. Make it internet-facing + ip targets
  # so chat_url is openable. (Dots in annotation keys are escaped for Helm.)
  dynamic "set" {
    for_each = local.detected_ingress_class == "alb" ? [1] : []
    content {
      name  = "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme"
      value = "internet-facing"
    }
  }

  dynamic "set" {
    for_each = local.detected_ingress_class == "alb" ? [1] : []
    content {
      name  = "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type"
      value = "ip"
    }
  }

  # IRSA: annotate the ServiceAccount with the Bedrock role we created.
  # The dotted annotation key is escaped so Helm treats it as one key.
  dynamic "set" {
    for_each = local.irsa ? [1] : []
    content {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = local.role_arn
    }
  }

  depends_on = [kubernetes_secret.credentials]
}

# --- Egress FirewallPolicy CRD ---------------------------------------------
# Generate from chart/librechat.yaml and apply to the same cluster. Re-runs when
# the config or the targeting changes. The destroy provisioner removes the CRD.
resource "null_resource" "egress_policy" {
  triggers = {
    config_sha = filesha256("${path.module}/chart/librechat.yaml")
    namespace  = var.namespace
    release    = var.release_name
    region     = var.bedrock_region
    kubeconfig = var.kubeconfig_path
    context    = var.kube_context
  }

  depends_on = [helm_release.librechat]

  provisioner "local-exec" {
    working_dir = path.module
    command     = <<-EOT
      set -e
      pip install -q -r egress-policy/requirements.txt >/dev/null 2>&1 || true
      printf 'BEDROCK_AWS_DEFAULT_REGION=%s\n' "${var.bedrock_region}" > egress-policy/.tf-generated.env
      python3 egress-policy/generate.py \
        --config chart/librechat.yaml \
        --env egress-policy/.tf-generated.env \
        --namespace ${var.namespace} \
        --pod-label app.kubernetes.io/name=${var.release_name} \
        --output egress-policy/firewall-policy.yaml
      kubectl --kubeconfig ${var.kubeconfig_path} ${local.kubectl_context_flag} apply -f egress-policy/firewall-policy.yaml
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    working_dir = path.module
    command     = <<-EOT
      kubectl --kubeconfig ${self.triggers.kubeconfig} ${self.triggers.context != "" ? "--context ${self.triggers.context}" : ""} delete -f egress-policy/firewall-policy.yaml --ignore-not-found || true
    EOT
  }
}

# --- chat_url discovery (best-effort) ---------------------------------------
# Read the ingress load-balancer address after install. ALB/LB provisioning is
# async, so the status may be empty for a few minutes; outputs.tf falls back to a
# fetch command when it is.
data "kubernetes_ingress_v1" "librechat" {
  count = local.ingress_enabled ? 1 : 0

  metadata {
    name      = var.release_name
    namespace = var.namespace
  }

  depends_on = [helm_release.librechat]
}
