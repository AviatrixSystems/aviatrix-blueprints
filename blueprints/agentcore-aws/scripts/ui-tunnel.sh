#!/usr/bin/env bash
# Port-forward the AgentCore VCA Streamlit probe UI to http://localhost:8501
# via EC2 Instance Connect Endpoint. No Session Manager plugin required.
#
#   ./scripts/ui-tunnel.sh                  # auto-discover instance, local port 8501
#   LOCAL_PORT=18501 ./scripts/ui-tunnel.sh # use a different local port
#
# Requires: AWS CLI v2 with ec2-instance-connect support, OpenSSH (macOS default).
set -euo pipefail

BLUEPRINT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REGION="${AWS_REGION:-us-east-2}"
LOCAL_PORT="${LOCAL_PORT:-8501}"

INSTANCE_ID="${1:-}"
if [[ -z "${INSTANCE_ID}" ]]; then
  INSTANCE_ID="$(cd "${BLUEPRINT_DIR}" && terraform output -raw client_invoker_instance_id 2>/dev/null || true)"
fi
if [[ -z "${INSTANCE_ID}" ]]; then
  echo "error: pass instance ID or run from blueprint dir with a populated state" >&2
  exit 64
fi

echo "Opening EICE tunnel to ${INSTANCE_ID}"
echo "  local:  http://localhost:${LOCAL_PORT}"
echo "  remote: 8501 on the client invoker EC2"
echo
echo "First run: type 'yes' to accept the host key. After that the UI is one Ctrl-C away."
echo

# AWS CLI's ec2-instance-connect ssh invokes your system ssh. We let users
# interactively accept the host key - non-TTY environments can pre-seed
# known_hosts via the SSH_ACCEPT_NEW env.
if [[ "${SSH_ACCEPT_NEW:-0}" == "1" ]]; then
  export SSH_OPTS="-o StrictHostKeyChecking=accept-new"
fi

exec aws ec2-instance-connect ssh \
  --region "${REGION}" \
  --instance-id "${INSTANCE_ID}" \
  --connection-type eice \
  --os-user ec2-user \
  --local-forwarding "${LOCAL_PORT}:localhost:8501"
