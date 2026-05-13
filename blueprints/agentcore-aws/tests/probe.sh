#!/usr/bin/env bash
# Runs the containment probes against the sample AgentCore Runtime and
# prints a pass/fail summary. Meant to be run from the client-invoker EC2
# (via SSM) after `terraform apply` finishes.
#
#   ./tests/probe.sh                     # uses AGENTCORE_RUNTIME_ARN + AWS_REGION env
#   ./tests/probe.sh <runtime-arn>       # explicit ARN override
set -euo pipefail

RUNTIME_ARN="${1:-${AGENTCORE_RUNTIME_ARN:-}}"
REGION="${AWS_REGION:-us-east-2}"
DATA_HOST="${AGENTCORE_DATA_HOST:-bedrock-agentcore.${REGION}.amazonaws.com}"

if [[ -z "${RUNTIME_ARN}" ]]; then
  echo "error: set AGENTCORE_RUNTIME_ARN or pass the ARN as the first argument" >&2
  exit 64
fi

echo "================================================================"
echo "AgentCore VCA containment probe"
echo "  region:        ${REGION}"
echo "  data host:     ${DATA_HOST}"
echo "  runtime ARN:   ${RUNTIME_ARN}"
echo "================================================================"

echo "-> DNS resolution of ${DATA_HOST} (should be a 10.50.20.x private IP)"
getent ahosts "${DATA_HOST}" | head -3 || true

OUT="$(mktemp)"
SESSION="probe-$(date +%s)-${RANDOM}-$(head /dev/urandom | tr -dc a-f0-9 | head -c 16)"
PAYLOAD_B64="$(printf '%s' '{"task":"run-probes"}' | base64 -w0 2>/dev/null || printf '%s' '{"task":"run-probes"}' | base64)"

echo
echo "-> invoking agent runtime (session=${SESSION})"
aws bedrock-agentcore invoke-agent-runtime \
  --region "${REGION}" \
  --agent-runtime-arn "${RUNTIME_ARN}" \
  --runtime-session-id "${SESSION}" \
  --payload "${PAYLOAD_B64}" \
  "${OUT}" >/dev/null

echo
echo "-> agent probe results:"
jq . "${OUT}"

echo
echo "-> expected containment posture:"
cat <<'EXPECTED'
  p1_bedrock_allowed    ok=true   (Bedrock via allowed-models WebGroup)
  p2_openai_denied      ok=false  (URLError/timeout - DCF default-deny)
  p3_attacker_denied    ok=false  (URLError/timeout - DCF default-deny)
  p4_dns_exfil_denied   ok=false  (timeout - DCF rule #50)
EXPECTED

echo
echo "================================================================"
echo "Now check CoPilot > Security > Distributed Cloud Firewall > FlowIQ"
echo "Filter on src_smart_group = ${SG_RUNTIME_NAME:-agentcore-vca-runtime-subnet}"
echo "to see allowed + denied flows with rule names."
echo "================================================================"
