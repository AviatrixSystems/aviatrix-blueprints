# =============================================================================
# Attacker loopback — observability for the exfil scenarios.
#
# Scenarios (LLM01, LLM05) POST to https://<sink>/<deploy_id>/<path> directly.
# The sink is Aviatrix-hosted on Vercel with a Let's Encrypt cert, so the
# agent's default trust store accepts it without an image rebuild and no
# customer-side DNS / cert plumbing is required.
#
# With DCF default-deny in place, the AgentCore spoke gateway sees the SNI
# avx-vca-sink.vercel.app, no permit rule matches, the connection is RST'd,
# and FlowIQ logs action=DENY with the real destination IP. Sink sees zero
# receipts -> UI loopback panel renders "0 POSTs received" (containment
# confirmed).
#
# If the customer flips the relevant DCF rule to PERMIT in CoPilot, the
# POST completes end-to-end, sink logs the receipt under the deploy_id,
# UI's GET /api/receipts/<id> returns it, panel flips to "1 POST received
# at <ts> - breach confirmed".
#
# -----------------------------------------------------------------------------
# Sink HTTP interface (base URL: https://avx-vca-sink.vercel.app)
# -----------------------------------------------------------------------------
#
#   POST /<deploy_id>/<any/path>
#     Records a receipt for the deploy. Path component after deploy_id is
#     stored verbatim. Request body captured up to ~4 KiB (truncated past
#     that in body_preview). Response: 202 Accepted, JSON
#     { ok: true, stored_at, receipt_id }. The agent uses this from
#     LLM01 (path: /collect) and LLM05 (path: from the injected URL).
#
#   GET /api/receipts/<deploy_id>?since=<unix_seconds>&limit=<n>
#     Returns receipts logged after `since`, newest first. Response:
#     200 JSON {
#       count:  int,
#       received: [
#         { received_at, method, path, bytes, source_ip, body_preview }
#       ]
#     }
#     UI polls this immediately after each scenario run.
#
#   GET /api/health
#     Liveness probe. Returns 200 JSON { ok: true } when sink is up.
#     UI uses this for the READY pill in the status strip
#     (hx-get every 60s).
#
# Receipts are scoped by deploy_id (computed below as a stable hash of
# name_prefix + account_id + region) so concurrent deployments never see
# each other's traffic. Retention is best-effort, capped per deploy_id
# in the sink's KV store.
# =============================================================================

variable "attacker_sink_host" {
  description = "Public hostname for the Aviatrix-hosted attack sink. Defaults to the Vercel production deployment; override for self-hosted demos."
  type        = string
  default     = "avx-vca-sink.vercel.app"
}

# Opaque per-deploy scoping key. Agent POSTs to /<deploy_id>/<path>; sink keys
# receipts by it; UI fetches via /api/receipts/<deploy_id>. Derived from
# config-known inputs (name_prefix + account + region) so it's stable across
# applies and doesn't introduce a circular dep with the runtime resource.
locals {
  attacker_sink_deploy_id = substr(sha256("${var.name_prefix}-${local.account_id}-${var.aws_region}"), 0, 16)
  attacker_sink_base      = "https://${var.attacker_sink_host}"
}

output "attacker_sink_host" {
  description = "Public hostname of the Aviatrix attack sink."
  value       = var.attacker_sink_host
}

output "attacker_sink_deploy_id" {
  description = "Opaque per-deploy scoping key. Sink stores receipts under this id; UI fetches receipts by it."
  value       = local.attacker_sink_deploy_id
}

output "attacker_sink_base_url" {
  description = "Sink base URL the runtime POSTs to (https://<host>); the agent appends /<deploy_id>/<scenario-path>."
  value       = local.attacker_sink_base
}
