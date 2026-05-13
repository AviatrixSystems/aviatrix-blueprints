# =============================================================================
# Aviatrix DCF MITM CA trust-store distribution.
#
# The CA PEM is fetched from the controller (/v2.5/api/dcf/mitm-ca) and
# written to avx-root-ca.pem by scripts/fetch-avx-ca.sh (idempotent).
#
# Distribution paths:
#   1. Runtime container: baked into the image at build time via the
#      Dockerfile (/usr/local/share/ca-certificates/avx-dcf-mitm.crt).
#      Reflected in the src-hash in agent.tf so rotations force a rebuild.
#
#   2. Browser + Code Interpreter (v2 primitives, deploy-on-demand): the
#      AgentCore Start*Session APIs accept a `certificates` parameter that
#      takes an ARN to a Secrets Manager secret containing the PEM. The
#      secret resource below exists today so the ARN is stable and known
#      to downstream TF configs that add Browser / Code Interpreter.
#
#   3. Workloads outside AgentCore that happen to live in a VCA-governed
#      spoke can pull the PEM from the same Secrets Manager secret as
#      part of their own bootstrap.
# =============================================================================

# PEM is gitignored and generated at deploy time by scripts/fetch-avx-ca.sh.
# Skip the secret + policy when it's missing so validate passes in CI and
# customers can deploy without DCF MITM trust distribution.
locals {
  mitm_ca_available = fileexists("${path.module}/avx-root-ca.pem")
}

resource "aws_secretsmanager_secret" "avx_mitm_ca" {
  count       = local.mitm_ca_available ? 1 : 0
  name        = "${local.name_prefix}-avx-mitm-ca"
  description = "Aviatrix DCF MITM root CA (public cert only). Distributed to AgentCore Browser / Code Interpreter trust stores."
  # Not sensitive: the PEM is the public half of a CA cert. The private key
  # stays on the Aviatrix controller / spoke gateway.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "avx_mitm_ca" {
  count         = local.mitm_ca_available ? 1 : 0
  secret_id     = aws_secretsmanager_secret.avx_mitm_ca[0].id
  secret_string = local.mitm_ca_available ? file("${path.module}/avx-root-ca.pem") : ""
}

# Grant the runtime execution role read access (preemptive; not used in v1
# but Browser / Code Interpreter service roles will need this once added).
data "aws_iam_policy_document" "read_avx_mitm_ca" {
  count = local.mitm_ca_available ? 1 : 0
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.avx_mitm_ca[0].arn]
  }
}

resource "aws_iam_role_policy" "runtime_read_avx_mitm_ca" {
  count  = local.mitm_ca_available ? 1 : 0
  name   = "read-avx-mitm-ca"
  role   = aws_iam_role.agentcore_runtime.id
  policy = data.aws_iam_policy_document.read_avx_mitm_ca[0].json
}
