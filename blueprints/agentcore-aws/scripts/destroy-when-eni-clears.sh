#!/usr/bin/env bash
# Waits for the AgentCore Runtime ENI (`agentic_ai` interface type, AWS-managed
# `ela-attach-*` attachment) to be released by AWS, then runs `terraform
# destroy -auto-approve` to finish cleaning up the runtime subnet, security
# group, and VPC. Use after a first `terraform destroy` errors out on
# DependencyViolation against `aws_subnet.agentcore_runtime` /
# `aws_security_group.runtime`.
#
# Why: the AgentCore Runtime keeps an AWS-managed ENI attached to the runtime
# subnet for many minutes after the Runtime resource is destroyed (observed:
# 30+ minutes; the attachment is `ela-attach-*` and cannot be detached by the
# customer - AWS returns OperationNotPermitted). Terraform polls the subnet
# delete on DependencyViolation and eventually errors out. Re-running destroy
# manually is annoying because you have to time it right. This script does the
# wait for you.
#
# Usage:
#   ./scripts/destroy-when-eni-clears.sh              # auto-detect subnet+region
#   ./scripts/destroy-when-eni-clears.sh <subnet-id>  # explicit subnet
#   POLL_INTERVAL=30 MAX_WAIT=7200 ./scripts/destroy-when-eni-clears.sh
#
# Defaults: poll every 60s for up to 3600s (1 hour). Tune via POLL_INTERVAL
# and MAX_WAIT env vars (seconds). Set TF_VAR_* env vars before invoking,
# same as a regular `terraform destroy`.
#
# Safe to ctrl-C and re-run. Idempotent.
set -euo pipefail

POLL_INTERVAL="${POLL_INTERVAL:-60}"
MAX_WAIT="${MAX_WAIT:-3600}"

BLUEPRINT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${BLUEPRINT_DIR}"

# Subnet ID: explicit CLI arg, else terraform output, else fail.
SUBNET_ID="${1:-}"
if [[ -z "${SUBNET_ID}" ]]; then
  SUBNET_ID="$(terraform output -raw agentcore_runtime_subnet_id 2>/dev/null || true)"
fi
if [[ -z "${SUBNET_ID}" ]]; then
  echo "error: could not determine runtime subnet id." >&2
  echo "       terraform output -raw agentcore_runtime_subnet_id returned empty," >&2
  echo "       and no subnet id was passed on the command line." >&2
  echo "" >&2
  echo "usage: $0 [<subnet-id>]" >&2
  exit 64
fi

# Region: AWS_REGION env wins, else AWS_DEFAULT_REGION, else aws configure.
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || true)}}"
if [[ -z "${REGION}" ]]; then
  echo "error: could not determine AWS region. set AWS_REGION env var." >&2
  exit 64
fi

echo "Watching runtime subnet : ${SUBNET_ID}"
echo "Region                  : ${REGION}"
echo "Poll interval           : ${POLL_INTERVAL}s"
echo "Max wait                : ${MAX_WAIT}s"
echo ""

START=$(date +%s)
while true; do
  NOW=$(date +%s)
  ELAPSED=$((NOW - START))

  if (( ELAPSED >= MAX_WAIT )); then
    echo "[$(date +%H:%M:%S)] ENI still attached after ${MAX_WAIT}s; giving up." >&2
    echo "                   Check manually:" >&2
    echo "                     aws ec2 describe-network-interfaces \\" >&2
    echo "                       --region ${REGION} \\" >&2
    echo "                       --filters Name=subnet-id,Values=${SUBNET_ID}" >&2
    exit 1
  fi

  ENI_COUNT="$(aws ec2 describe-network-interfaces \
    --region "${REGION}" \
    --filters "Name=subnet-id,Values=${SUBNET_ID}" \
    --query 'NetworkInterfaces | length(@)' \
    --output text 2>/dev/null || echo "?")"

  if [[ "${ENI_COUNT}" == "0" ]]; then
    echo "[$(date +%H:%M:%S)] ENI gone after ${ELAPSED}s. Running terraform destroy."
    break
  fi

  echo "[$(date +%H:%M:%S)] elapsed=${ELAPSED}s ENI_count=${ENI_COUNT} - waiting..."
  sleep "${POLL_INTERVAL}"
done

terraform destroy -auto-approve
