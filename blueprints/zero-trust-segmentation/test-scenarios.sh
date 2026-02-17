#!/bin/bash

# ============================================================================
# Zero Trust Segmentation - Test Scenarios
# ============================================================================
# This script automates connectivity testing to validate DCF policies
#
# Prerequisites:
# - Terraform deployment completed successfully
# - AWS CLI configured with appropriate credentials
# - jq installed for JSON parsing
#
# Usage: ./test-scenarios.sh
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get VM instance IDs and IPs from Terraform output
echo "Fetching deployment information..."
DEV_VM_ID=$(terraform output -json test_vm_ids | jq -r '.dev')
PROD_VM_ID=$(terraform output -json test_vm_ids | jq -r '.prod')
DB_VM_ID=$(terraform output -json test_vm_ids | jq -r '.db')

DEV_IP=$(terraform output -json test_vm_private_ips | jq -r '.dev')
PROD_IP=$(terraform output -json test_vm_private_ips | jq -r '.prod')
DB_IP=$(terraform output -json test_vm_private_ips | jq -r '.db')

AWS_REGION=$(terraform output -raw aws_region || echo "us-east-1")

echo ""
echo "==================================================================="
echo "Zero Trust Segmentation Test Scenarios"
echo "==================================================================="
echo ""
echo "Environment Details:"
echo "  Dev VM:  ${DEV_VM_ID} (${DEV_IP})"
echo "  Prod VM: ${PROD_VM_ID} (${PROD_IP})"
echo "  DB VM:   ${DB_VM_ID} (${DB_IP})"
echo ""

# Function to run command on EC2 instance via SSM
run_on_vm() {
    local instance_id=$1
    local command=$2

    aws ssm send-command \
        --instance-ids "${instance_id}" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"${command}\"]" \
        --region "${AWS_REGION}" \
        --output json > /tmp/ssm_command.json

    command_id=$(jq -r '.Command.CommandId' /tmp/ssm_command.json)

    # Wait for command to complete
    sleep 3

    # Get command output
    aws ssm get-command-invocation \
        --command-id "${command_id}" \
        --instance-id "${instance_id}" \
        --region "${AWS_REGION}" \
        --output json > /tmp/ssm_output.json

    status=$(jq -r '.Status' /tmp/ssm_output.json)
    output=$(jq -r '.StandardOutputContent' /tmp/ssm_output.json)

    echo "${status}|${output}"
}

# Function to test connectivity
test_connectivity() {
    local scenario=$1
    local source_vm=$2
    local dest_ip=$3
    local expected=$4

    echo "-------------------------------------------------------------------"
    echo "Scenario ${scenario}"
    echo "-------------------------------------------------------------------"

    echo "Running: ping -c 3 -W 2 ${dest_ip}"
    result=$(run_on_vm "${source_vm}" "ping -c 3 -W 2 ${dest_ip}")

    status=$(echo "${result}" | cut -d'|' -f1)
    output=$(echo "${result}" | cut -d'|' -f2)

    if [[ "${status}" == "Success" ]] && echo "${output}" | grep -q "3 received"; then
        if [[ "${expected}" == "ALLOW" ]]; then
            echo -e "${GREEN}✓ PASS${NC} - Connectivity allowed as expected"
        else
            echo -e "${RED}✗ FAIL${NC} - Connectivity allowed but should be blocked!"
        fi
    else
        if [[ "${expected}" == "DENY" ]]; then
            echo -e "${GREEN}✓ PASS${NC} - Connectivity blocked as expected"
        else
            echo -e "${RED}✗ FAIL${NC} - Connectivity blocked but should be allowed!"
        fi
    fi
    echo ""
}

# Scenario 1: Dev → DB (SHOULD BE BLOCKED)
echo ""
test_connectivity \
    "1: Dev trying to access DB (SHOULD BE BLOCKED)" \
    "${DEV_VM_ID}" \
    "${DB_IP}" \
    "DENY"

# Scenario 2: Prod → DB (SHOULD BE ALLOWED)
test_connectivity \
    "2: Prod accessing DB (SHOULD BE ALLOWED)" \
    "${PROD_VM_ID}" \
    "${DB_IP}" \
    "ALLOW"

# Scenario 3: Dev → Prod (SHOULD BE ALLOWED - ICMP only)
test_connectivity \
    "3: Dev accessing Prod (SHOULD BE ALLOWED)" \
    "${DEV_VM_ID}" \
    "${PROD_IP}" \
    "ALLOW"

# Scenario 4: Prod → Dev (SHOULD BE BLOCKED)
test_connectivity \
    "4: Prod trying to access Dev (SHOULD BE BLOCKED)" \
    "${PROD_VM_ID}" \
    "${DEV_IP}" \
    "DENY"

echo "==================================================================="
echo "Test Summary"
echo "==================================================================="
echo ""
echo "To view blocked traffic in CoPilot:"
echo "1. Navigate to Security > Distributed Cloud Firewall > Monitor"
echo "2. Filter by time range: Last 15 minutes"
echo "3. Look for DENIED traffic from:"
echo "   - Dev (${DEV_IP}) → DB (${DB_IP})"
echo "   - Prod (${PROD_IP}) → Dev (${DEV_IP})"
echo ""
echo "To view allowed traffic:"
echo "4. Filter for PERMITTED traffic:"
echo "   - Prod (${PROD_IP}) → DB (${DB_IP})"
echo "   - Dev (${DEV_IP}) → Prod (${PROD_IP})"
echo ""
echo "==================================================================="
