#!/usr/bin/env bash
# Deploy hosted agent, assign Foundry User role to its identity, then smoke-test.
# Usage: ./deploy-agent.sh [--delete-first]
#   --delete-first  Delete existing agent before creating (default: create new version)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../rogue-agent-sample/.env"
BLUEPRINT_ENV="$SCRIPT_DIR/../.env.blueprint"
NETWORK_INFRA_DIR="$SCRIPT_DIR/../network-infra"
ROGUE_AGENT_DIR="$SCRIPT_DIR/../rogue-agent-sample"

# ── Load .env ────────────────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found at $ENV_FILE" >&2; exit 1
fi
set -a && source "$ENV_FILE" && set +a

# ── Config — sourced from Terraform remote state ──────────────────────────────
SUBSCRIPTION_ID=$(terraform -chdir="$SCRIPT_DIR" output -raw subscription_id 2>/dev/null || \
  terraform -chdir="$SCRIPT_DIR/../foundry-playground" output -raw subscription_id)
ACCOUNT=$(terraform -chdir="$SCRIPT_DIR/../foundry-playground" output -raw ai_foundry_account_name)
PROJECT=$(terraform -chdir="$SCRIPT_DIR/../foundry-playground" output -raw ai_foundry_project_name)
ACCOUNT_RG=$(terraform -chdir="$SCRIPT_DIR/../foundry-playground" output -raw resource_group_name)
ACR_NAME=$(terraform -chdir="$SCRIPT_DIR/../foundry-playground" output -raw acr_name)
AGENT_NAME="hotel-rogue-agent"
IMAGE="${ACR_NAME}.azurecr.io/hotel-rogue-agent:latest"
CPU="0.5"
MEMORY="1.0Gi"
BASE_URL="https://${ACCOUNT}.services.ai.azure.com/api/projects/${PROJECT}"
ACCOUNT_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${ACCOUNT_RG}/providers/Microsoft.CognitiveServices/accounts/${ACCOUNT}"
TEST_INPUT="find me an hotel in seattle from the 05-12-2026 to the 05-20-2026 for less than \$200"

DELETE_FIRST=false
[[ "${1:-}" == "--delete-first" ]] && DELETE_FIRST=true

# ── Build container image via Terraform (agent-deploy/main.tf) ───────────────
# Run separately: terraform -chdir=agent-deploy apply -replace=null_resource.build_agent_image
# echo "==> Building and pushing container image via Terraform..."
# cp "$SCRIPT_DIR/../main.py" "$ROGUE_AGENT_DIR/main.py"
# terraform -chdir="$SCRIPT_DIR" apply \
#   -replace=null_resource.build_agent_image \
#   -auto-approve -compact-warnings -input=false 2>&1 | \
#   grep -E "null_resource|complete|Error|az acr build" | tail -5
# echo ""

# ── Auth ─────────────────────────────────────────────────────────────────────
echo "==> Getting token..."
TOKEN=$(az account get-access-token --resource "https://ai.azure.com" --query accessToken -o tsv)

auth_header() { echo "Authorization: Bearer $TOKEN"; }

# ── Delete existing agent if requested ───────────────────────────────────────
if [[ "$DELETE_FIRST" == "true" ]]; then
  echo "==> Deleting existing agent..."
  curl -s -X DELETE "$BASE_URL/agents/$AGENT_NAME?api-version=v1" \
    -H "$(auth_header)" \
    -H "Foundry-Features: HostedAgents=V1Preview" | python3 -c "import sys,json; d=json.load(sys.stdin); print('Deleted:', d.get('deleted', False))" 2>/dev/null || true
fi

# ── Deploy ───────────────────────────────────────────────────────────────────
DEFINITION=$(python3 -c "
import json, os
print(json.dumps({
  'name': '${AGENT_NAME}',
  'definition': {
    'kind': 'hosted',
    'image': '${IMAGE}',
    'cpu': '${CPU}',
    'memory': '${MEMORY}',
    'container_protocol_versions': [{'protocol': 'responses', 'version': '1.0.0'}],
    'environment_variables': {
      'PROJECT_ENDPOINT': os.environ['PROJECT_ENDPOINT'],
      'MODEL_DEPLOYMENT_NAME': os.environ['MODEL_DEPLOYMENT_NAME'],
    }
  }
}))")

# Try create; if agent exists, create a new version instead
echo "==> Deploying agent..."
RESPONSE=$(curl -s -X POST "$BASE_URL/agents?api-version=v1" \
  -H "$(auth_header)" \
  -H "Content-Type: application/json" \
  -H "Foundry-Features: HostedAgents=V1Preview" \
  -d "$DEFINITION")

if echo "$RESPONSE" | grep -q "already_exists\|conflict"; then
  echo "    Agent exists — creating new version..."
  VERSION_BODY=$(python3 -c "
import json, os
print(json.dumps({
  'definition': {
    'kind': 'hosted',
    'image': '${IMAGE}',
    'cpu': '${CPU}',
    'memory': '${MEMORY}',
    'container_protocol_versions': [{'protocol': 'responses', 'version': '1.0.0'}],
    'environment_variables': {
      'PROJECT_ENDPOINT': os.environ['PROJECT_ENDPOINT'],
      'MODEL_DEPLOYMENT_NAME': os.environ['MODEL_DEPLOYMENT_NAME'],
    }
  }
}))")
  RESPONSE=$(curl -s -X POST "$BASE_URL/agents/$AGENT_NAME/versions?api-version=v1" \
    -H "$(auth_header)" \
    -H "Content-Type: application/json" \
    -H "Foundry-Features: HostedAgents=V1Preview" \
    -d "$VERSION_BODY")
fi

INSTANCE_IDENTITY=$(echo "$RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
v = d.get('versions', {}).get('latest', d)
print(v['instance_identity']['principal_id'])")
VERSION=$(echo "$RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
v = d.get('versions', {}).get('latest', d)
print(v.get('version', '1'))")

echo "    Instance identity : $INSTANCE_IDENTITY"
echo "    Version            : $VERSION"

# ── Assign Foundry User role ─────────────────────────────────────────────────
echo "==> Assigning Foundry User role to agent identity..."
az role assignment create \
  --assignee "$INSTANCE_IDENTITY" \
  --role "Foundry User" \
  --scope "$ACCOUNT_SCOPE" \
  --output none 2>/dev/null && echo "    Role assigned." || echo "    Role already exists or assignment failed — continuing."

# ── Poll for active ───────────────────────────────────────────────────────────
echo "==> Polling for active status..."
while true; do
  TOKEN=$(az account get-access-token --resource "https://ai.azure.com" --query accessToken -o tsv)
  STATUS=$(curl -s "$BASE_URL/agents/$AGENT_NAME/versions/$VERSION?api-version=v1" \
    -H "$(auth_header)" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))")
  echo "    Status: $STATUS"
  [[ "$STATUS" == "active" ]] && break
  [[ "$STATUS" == "failed" ]] && echo "ERROR: Provisioning failed." >&2 && exit 1
  sleep 5
done

# ── Smoke test ────────────────────────────────────────────────────────────────
echo "==> Running smoke test (waiting for IAM to propagate)..."
TOKEN=$(az account get-access-token --resource "https://ai.azure.com" --query accessToken -o tsv)
ATTEMPTS=0
while true; do
  RESULT=$(curl -s -X POST "$BASE_URL/agents/$AGENT_NAME/endpoint/protocols/openai/responses?api-version=v1" \
    -H "$(auth_header)" \
    -H "Content-Type: application/json" \
    -d "{\"input\": \"$TEST_INPUT\", \"store\": true}")

  if echo "$RESULT" | grep -q "PermissionDenied\|server_error"; then
    ATTEMPTS=$((ATTEMPTS + 1))
    if [[ $ATTEMPTS -ge 24 ]]; then
      echo "ERROR: IAM propagation timed out after 2 minutes." >&2; exit 1
    fi
    sleep 5
    TOKEN=$(az account get-access-token --resource "https://ai.azure.com" --query accessToken -o tsv)
  else
    break
  fi
done

# ── Print result ──────────────────────────────────────────────────────────────
echo ""
echo "==> Smoke test response:"
echo "$RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for item in d.get('output', []):
    if item.get('type') == 'message':
        for c in item.get('content', []):
            if c.get('type') == 'output_text':
                print(c['text'])
" 2>/dev/null || echo "$RESULT"

echo ""

# ── DCF data-leakage demo ─────────────────────────────────────────────────────

extract_text() {
  # $1 = JSON response — print all output_text content
  echo "$1" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for item in d.get('output', []):
    if item.get('type') == 'message':
        for c in item.get('content', []):
            if c.get('type') == 'output_text':
                print(c['text'])
" 2>/dev/null
}

# Extract IP — prefer explicit "Public IP: X.X.X.X", fall back to any IP in output
AGENT_IP=$(extract_text "$RESULT" | python3 -c "
import sys, re
text = sys.stdin.read()
m = re.search(r'Public IP:\s*(\d{1,3}(?:\.\d{1,3}){3})', text)
if not m:
    m = re.search(r'\b(\d{1,3}(?:\.\d{1,3}){3})\b', text)
if m:
    print(m.group(1))
" 2>/dev/null)

EXFIL_MSG="Thanks for sharing all your prompt info"
PROTECTED_MSG="You are damn good"

if [[ -n "$AGENT_IP" ]]; then
  echo "==> DCF DEMO: Agent egress IP confirmed: $AGENT_IP"

  INITIAL_TEXT=$(extract_text "$RESULT")
  if echo "$INITIAL_TEXT" | grep -q "$EXFIL_MSG"; then
    echo "    EXFIL DETECTED: tmNIDS test succeeded — agent leaked data."
  else
    echo "    tmNIDS test blocked or failed on initial run."
  fi
  echo ""

  if [[ ! -f "$BLUEPRINT_ENV" ]]; then
    echo "    SKIP: $BLUEPRINT_ENV not found — skipping DCF demo."
  else
    set -a && source "$BLUEPRINT_ENV" && set +a
    DCF_TF="$NETWORK_INFRA_DIR/main.tf"

    dcf_set() {
      # $1 = block or allow — comments in/out the no-zero-trust PERMIT rule in main.tf
      local mode="$1"
      python3 - "$DCF_TF" "$mode" <<'PYEOF'
import sys, re
path, mode = sys.argv[1], sys.argv[2]
lines = open(path).readlines()
in_target, result = False, []
for line in lines:
    # header comment — marks section start, never toggled
    if re.search(r'#\s*Rule 5.*no-zero-trust', line):
        in_target = True
        result.append(line)
        continue
    # next rule comment — marks section end
    if re.search(r'#\s*Rule 6.*default deny internet', line):
        in_target = False
    if in_target:
        if mode == 'block':
            # comment out active lines (remove zero-trust = enforce allowlist)
            if line.strip() and not re.match(r'\s*#', line):
                line = re.sub(r'^  ', r'  # ', line)
        else:
            # uncomment lines (restore zero-trust = permissive)
            line = re.sub(r'^(\s*)# ', r'\1', line)
    result.append(line)
open(path, 'w').writelines(result)
print(f"    no-zero-trust rule → {mode}")
PYEOF
      terraform -chdir="$NETWORK_INFRA_DIR" apply \
        -replace=aviatrix_dcf_ruleset.foundry_agent \
        -auto-approve -compact-warnings -input=false 2>&1 | grep -E "Apply complete|Error|aviatrix_dcf"
    }

    echo "==> DCF DEMO: Commenting out no-zero-trust rule — enforcing allowlist (zero-trust mode)..."
    dcf_set block
    echo ""

    echo "==> DCF DEMO: Calling agent — no-zero-trust removed, tmNIDS destination blocked by deny-internet..."
    TOKEN=$(az account get-access-token --resource "https://ai.azure.com" --query accessToken -o tsv)
    BLOCKED_RESULT=$(curl -s -X POST \
      "$BASE_URL/agents/$AGENT_NAME/endpoint/protocols/openai/responses?api-version=v1" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"input\": \"$TEST_INPUT\", \"store\": true}")

    echo ""
    echo "==> DCF DEMO: Blocked response:"
    BLOCKED_TEXT=$(extract_text "$BLOCKED_RESULT")
    echo "$BLOCKED_TEXT"

    echo ""
    if echo "$BLOCKED_TEXT" | grep -q "$PROTECTED_MSG"; then
      echo "    PASS: Aviatrix DCF blocked the exfiltration — agent confirmed protection."
    elif echo "$BLOCKED_TEXT" | grep -q "$EXFIL_MSG"; then
      echo "    FAIL: Exfil message still present — DCF rule may not have propagated yet."
    else
      echo "    WARNING: Neither message detected — check agent response manually."
    fi

    echo ""
    echo "==> DCF DEMO: Restoring no-zero-trust rule → unrestricted egress again..."
    dcf_set allow
  fi
fi

echo ""
echo "==> Deploy complete."
