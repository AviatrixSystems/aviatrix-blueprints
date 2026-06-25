#!/usr/bin/env bash
set -euo pipefail

if ! command -v terraform >/dev/null 2>&1 || ! command -v aws >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "requires terraform, aws, and jq" >&2
  exit 1
fi

json="$(terraform output -json)"
region="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
subnets="$(jq -r '.agent_private_subnet_ids.value[]' <<<"$json")"

for subnet in $subnets; do
  echo "==> private subnet: $subnet"
  route_table_id="$(aws ec2 describe-route-tables \
    --region "$region" \
    --filters Name=association.subnet-id,Values="$subnet" \
    --query 'RouteTables[0].RouteTableId' --output text)"
  if [ -z "$route_table_id" ] || [ "$route_table_id" = "None" ]; then
    echo "  no explicit route table association found" >&2
    continue
  fi
  echo "  route_table=$route_table_id"
  aws ec2 describe-route-tables --region "$region" --route-table-ids "$route_table_id" \
    --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`]' --output table
done
