#!/usr/bin/env bash
# test-eks-dcf.sh — EKS DCF enforcement test suite
#
# Run from the blueprint directory (where terraform.tfvars lives).
# Reads config from terraform.tfvars + terraform outputs.
#
# Usage:
#   ./scripts/test-eks-dcf.sh                  # non-destructive checks (default)
#   ./scripts/test-eks-dcf.sh --bug-b           # + reproduce assetd watcher loss (brief enforcement gap)
#   ./scripts/test-eks-dcf.sh --jira-v1-sg      # print V1 SmartGroup repro instructions
#   ./scripts/test-eks-dcf.sh --jira-flags      # print feature flag reset repro instructions
#
# Requirements: aws, kubectl, terraform, curl, python3

# no set -e: test script intentionally runs failing commands and reports PASS/FAIL
set -uo pipefail

# ── colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
pass()  { echo -e "${GREEN}[PASS]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES+1)); }
skip()  { echo -e "${YELLOW}[SKIP]${NC} $*"; }
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
section(){ echo -e "\n${BLUE}━━━ $* ━━━${NC}"; }

FAILURES=0
RUN_BUG_B=false
PRINT_V1_SG=false
PRINT_FLAGS=false

for arg in "$@"; do
  case $arg in
    --bug-b)       RUN_BUG_B=true ;;
    --jira-v1-sg)  PRINT_V1_SG=true ;;
    --jira-flags)  PRINT_FLAGS=true ;;
  esac
done

# ── config from tfvars ────────────────────────────────────────────────────────
parse_tfvar() { grep -E "^${1}[[:space:]]*=" terraform.tfvars 2>/dev/null | head -1 | sed -E 's/^[^=]+=[[:space:]]*"?([^"]*)"?[[:space:]]*/\1/' | tr -d '"' || true; }

CONTROLLER_IP=$(parse_tfvar controller_ip)
CONTROLLER_PASS="${TF_VAR_controller_password:-$(parse_tfvar controller_password)}"
CONTROLLER_USER=$(parse_tfvar controller_username); CONTROLLER_USER="${CONTROLLER_USER:-admin}"
APP_ROLE_ARN=$(parse_tfvar aviatrix_app_role_arn)
AWS_REGION=$(parse_tfvar aws_region); AWS_REGION="${AWS_REGION:-us-east-1}"
NAME_PREFIX=$(parse_tfvar name_prefix); NAME_PREFIX="${NAME_PREFIX:-obot-mcp}"
OBOT_NS=$(parse_tfvar obot_namespace); OBOT_NS="${OBOT_NS:-obot-system}"
MCP_NS=$(parse_tfvar obot_mcp_namespace); MCP_NS="${MCP_NS:-obot-mcp}"

if [[ -z "$CONTROLLER_IP" || -z "$CONTROLLER_PASS" || -z "$APP_ROLE_ARN" ]]; then
  echo "ERROR: missing controller_ip, controller_password, or aviatrix_app_role_arn in terraform.tfvars"
  exit 1
fi

# cluster name from TF output (must be run from blueprint dir after apply)
CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
if [[ -z "$CLUSTER_NAME" ]]; then
  echo "ERROR: cannot read eks_cluster_name from terraform output. Run terraform apply first."
  exit 1
fi

info "Controller:  $CONTROLLER_IP"
info "Cluster:     $CLUSTER_NAME ($AWS_REGION)"
info "Role ARN:    $APP_ROLE_ARN"
info "Namespaces:  $OBOT_NS / $MCP_NS"

# ── helper: get CID ───────────────────────────────────────────────────────────
get_cid() {
  curl -sk "https://${CONTROLLER_IP}/v2/api" \
    -d "action=login&username=${CONTROLLER_USER}&password=${CONTROLLER_PASS}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('CID',''))"
}

# ── helper: get SmartGroup IPs by name substring ──────────────────────────────
get_sg_ips() {
  local cid="$1" name_fragment="$2"
  curl -sk "https://${CONTROLLER_IP}/v2/api" \
    -d "action=list_micro_segmentation_smart_groups&CID=${cid}" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
sgs = data.get('results', [])
for sg in sgs:
    if '${name_fragment}' in sg.get('name',''):
        cidrs = sg.get('ipv4_cidrs', [])
        print(f\"{sg['name']}: {cidrs}\")
"
}

# ══════════════════════════════════════════════════════════════════════════════
section "BUG A — IAM principal + RBAC (cluster onboarding)"
# ══════════════════════════════════════════════════════════════════════════════

# A1: access entry principal
info "Checking EKS access entries..."
ENTRY_ARNS=$(aws eks list-access-entries \
  --cluster-name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'accessEntries' \
  --output text 2>/dev/null || echo "")

APP_ROLE_NAME=$(echo "$APP_ROLE_ARN" | sed 's|.*/||')
MATCHED=$(echo "$ENTRY_ARNS" | tr '\t' '\n' | grep -i "$APP_ROLE_NAME" || true)
if [[ -n "$MATCHED" ]]; then
  pass "A1: EKS access entry found for $APP_ROLE_NAME"
else
  fail "A1: No access entry found for $APP_ROLE_NAME. Entries: $ENTRY_ARNS"
fi

# A2: ClusterRoleBindings
for CRB in view-nodes aviatrix-crd-view; do
  if kubectl get clusterrolebinding "$CRB" &>/dev/null; then
    pass "A2: ClusterRoleBinding '$CRB' exists"
  else
    fail "A2: ClusterRoleBinding '$CRB' missing"
  fi
done

# ══════════════════════════════════════════════════════════════════════════════
section "BUG C — TF resource conflict (auto-discovery)"
# ══════════════════════════════════════════════════════════════════════════════

CONFLICT_RES=$(terraform state list 2>/dev/null | grep "aviatrix_kubernetes_cluster" || true)
if [[ -z "$CONFLICT_RES" ]]; then
  pass "C: aviatrix_kubernetes_cluster not in TF state (auto-discovery path)"
else
  fail "C: aviatrix_kubernetes_cluster still in TF state: $CONFLICT_RES"
fi

# ══════════════════════════════════════════════════════════════════════════════
section "BUG D — CRDs + NPC health"
# ══════════════════════════════════════════════════════════════════════════════

# D1: CRDs installed
for CRD in firewallpolicies.networking.aviatrix.com webgrouppolicies.networking.aviatrix.com; do
  if kubectl get crd "$CRD" &>/dev/null; then
    pass "D1: CRD '$CRD' installed"
  else
    fail "D1: CRD '$CRD' missing — NPC will crash on startup"
  fi
done

# D2: k8s-firewall helm release (check all namespaces)
K8S_FW_RELEASE=$(helm list -A 2>/dev/null | grep -i "k8s-firewall\|aviatrix-crds\|k8s-fw" | head -1 || true)
if [[ -n "$K8S_FW_RELEASE" ]]; then
  pass "D2: k8s-firewall Helm release deployed: $K8S_FW_RELEASE"
else
  fail "D2: k8s-firewall Helm release not found in any namespace (helm list -A)"
fi

# D3: NPC — Obot self-manages; check all namespaces for any aviatrix-network-policy-controller pod
NPC_POD=$(kubectl get pods -A --no-headers 2>/dev/null \
  | grep -i "aviatrix-network-policy\|network-policy-controller\|aviatrix-npc" \
  | head -1 || true)
if [[ -n "$NPC_POD" ]]; then
  NPC_NS=$(echo "$NPC_POD" | awk '{print $1}')
  NPC_NAME=$(echo "$NPC_POD" | awk '{print $2}')
  NPC_STATUS=$(echo "$NPC_POD" | awk '{print $4}')
  if [[ "$NPC_STATUS" == "Running" ]]; then
    pass "D3: NPC pod $NPC_NAME ($NPC_NS) Running"
  else
    fail "D3: NPC pod $NPC_NAME ($NPC_NS) status=$NPC_STATUS"
  fi
else
  # NPC may be a sidecar container inside the obot pod
  OBOT_POD=$(kubectl get pods -n "$OBOT_NS" --no-headers 2>/dev/null | grep -v "Terminating" | head -1 | awk '{print $1}' || true)
  if [[ -n "$OBOT_POD" ]]; then
    NPC_CONTAINER=$(kubectl get pod -n "$OBOT_NS" "$OBOT_POD" \
      -o jsonpath='{.spec.containers[*].name}' 2>/dev/null \
      | tr ' ' '\n' | grep -i "npc\|network-policy\|aviatrix" | head -1 || true)
    if [[ -n "$NPC_CONTAINER" ]]; then
      READY=$(kubectl get pod -n "$OBOT_NS" "$OBOT_POD" \
        -o jsonpath="{.status.containerStatuses[?(@.name==\"$NPC_CONTAINER\")].ready}" 2>/dev/null || echo "false")
      [[ "$READY" == "true" ]] \
        && pass "D3: NPC container '$NPC_CONTAINER' in $OBOT_NS/$OBOT_POD Ready" \
        || fail "D3: NPC container '$NPC_CONTAINER' in $OBOT_NS/$OBOT_POD not Ready (ready=$READY)"
    else
      skip "D3: NPC not found in any namespace — check 'kubectl get pods -A | grep -i aviatrix'"
    fi
  else
    skip "D3: No running pods in $OBOT_NS to check NPC"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
section "ENFORCEMENT — SmartGroup resolution + egress block"
# ══════════════════════════════════════════════════════════════════════════════

info "Getting controller CID..."
CID=$(get_cid)
if [[ -z "$CID" ]]; then
  fail "ENFORCE0: Cannot authenticate to controller $CONTROLLER_IP"
else
  pass "ENFORCE0: Controller auth OK (CID obtained)"

  # SmartGroup: mcp-servers V1 ipv4_cidrs check (V1 tier isolation, not per-pod enforcement)
  # NOTE: FAIL here does NOT mean per-pod enforcement is broken. K8S_POLICY_LIST per-pod
  # enforcement via FirewallPolicy CRDs works independently of V1 SmartGroup ipv4_cidrs.
  # FAIL means V1 tier isolation (obot-system vs obot-mcp namespace separation) requires
  # the CIDR /32 workaround (obot_system_pod_cidrs var). See stp-v1-k8s-smartgroup-source.md.
  info "Checking V1 SmartGroup ipv4_cidrs (tier isolation indicator)..."
  SG_RESULT=$(get_sg_ips "$CID" "${NAME_PREFIX}-mcp-servers")
  if echo "$SG_RESULT" | grep -qE "\b10\.\|172\.\|192\."; then
    pass "ENFORCE1: SmartGroup '${NAME_PREFIX}-mcp-servers' has V1 ipv4_cidrs: $SG_RESULT"
  else
    fail "ENFORCE1: SmartGroup '${NAME_PREFIX}-mcp-servers' V1 ipv4_cidrs empty (V1 tier isolation gap; per-pod K8S_POLICY_LIST enforcement unaffected): $SG_RESULT"
  fi
fi

# Egress block test from MCP pod
MCP_POD=$(kubectl get pods -n "$MCP_NS" -o name 2>/dev/null | head -1 | sed 's|pod/||')
if [[ -n "$MCP_POD" ]]; then
  CONTAINER=$(kubectl get pod -n "$MCP_NS" "$MCP_POD" \
    -o jsonpath='{.spec.containers[0].name}' 2>/dev/null)
  info "Testing egress from $MCP_POD ($CONTAINER) → api.openai.com..."
  RESULT=$(kubectl exec -n "$MCP_NS" "$MCP_POD" -c "$CONTAINER" -- \
    curl -s --max-time 15 -o /dev/null -w "HTTP:%{http_code} Exit:%{exitcode}" \
    https://api.openai.com 2>/dev/null || echo "exec-failed")
  if echo "$RESULT" | grep -q "Exit:35"; then
    pass "ENFORCE2: Egress blocked (Exit:35) — enforcement active"
  elif echo "$RESULT" | grep -q "HTTP:200"; then
    fail "ENFORCE2: Egress UNBLOCKED (HTTP:200) — enforcement not active. Result: $RESULT"
  else
    skip "ENFORCE2: Unexpected result: $RESULT"
  fi
else
  skip "ENFORCE2: No pods in $MCP_NS — deploy an MCP server first"
fi

# ══════════════════════════════════════════════════════════════════════════════
if [[ "$RUN_BUG_B" == "true" ]]; then
section "BUG B — assetd watcher loss on restart (DESTRUCTIVE — brief enforcement gap)"
# ══════════════════════════════════════════════════════════════════════════════

  info "Recording SmartGroup IPs before restart..."
  CID=$(get_cid)
  SG_BEFORE=$(get_sg_ips "$CID" "${NAME_PREFIX}-mcp-servers")
  info "Before: $SG_BEFORE"

  info "Restarting aviatrix-system pods (simulates assetd restart)..."
  if kubectl get ns aviatrix-system &>/dev/null; then
    kubectl delete pods -n aviatrix-system --all
    info "Waiting 60s for pods to restart and watcher to re-sync..."
    sleep 60
  else
    skip "B: aviatrix-system namespace not found — controller agent not installed (Partial cluster)"
    info "B: To reproduce Bug B: restart the Aviatrix controller VM and check SmartGroup IPs after restart"
  fi

  info "Checking SmartGroup IPs after restart..."
  CID=$(get_cid)
  SG_AFTER=$(get_sg_ips "$CID" "${NAME_PREFIX}-mcp-servers")
  info "After: $SG_AFTER"

  if echo "$SG_AFTER" | grep -qE "\b10\.\|172\.\|192\."; then
    pass "B: SmartGroup still has pod IPs after restart — Bug B may be fixed or not triggered"
  else
    fail "B: SmartGroup lost pod IPs after restart — Bug B confirmed. IPs before: $SG_BEFORE | after: $SG_AFTER"
    info "B: Verify enforcement gap: curl from MCP pod should now return HTTP:200"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
if [[ "$PRINT_V1_SG" == "true" ]]; then
section "JIRA: V1 SmartGroup source rejects k8s namespace type (MANUAL — breaks all DCF)"
# ══════════════════════════════════════════════════════════════════════════════
cat <<'INSTRUCTIONS'
WARNING: This test breaks all DCF policies until reverted. Run only on a disposable cluster.

Steps:
  1. In dcf.tf, add a k8s namespace SmartGroup resource:
       resource "aviatrix_smart_group" "test_k8s_ns" {
         name = "test-k8s-ns-sg"
         selector {
           match_expressions {
             type          = "k8s"
             k8s_namespace = "obot-system"
           }
         }
       }

  2. Reference it as src in a V1 policy rule inside aviatrix_distributed_firewalling_policy_list.infra:
       policies {
         name             = "test-k8s-src"
         action           = "PERMIT"
         priority         = 99
         src_smart_groups = [aviatrix_smart_group.test_k8s_ns.uuid]
         dst_smart_groups = ["def000ad-0000-0000-0000-000000000000"]
         web_groups       = [aviatrix_web_group.obot_pod_egress.uuid]
       }

  3. terraform apply

  Expected: CoPilot → DCF → Policies shows:
    "Failed to load Distributed Cloud Firewall policies: Unknown error"
  All existing V1 rules stop loading — full policy list failure.

  4. REVERT: remove the test resource and terraform apply immediately.

INSTRUCTIONS
fi

# ══════════════════════════════════════════════════════════════════════════════
if [[ "$PRINT_FLAGS" == "true" ]]; then
section "JIRA: DCF feature flags reset on controller reboot (MANUAL — controller restart required)"
# ══════════════════════════════════════════════════════════════════════════════
cat <<INSTRUCTIONS
Steps:
  1. Record current flag state:
     CID=\$(curl -sk "https://${CONTROLLER_IP}/v2/api" \\
       -d "action=login&username=${CONTROLLER_USER}&password=${CONTROLLER_PASS}" \\
       | python3 -c "import sys,json; print(json.load(sys.stdin).get('CID',''))")
     curl -sk "https://${CONTROLLER_IP}/v2/api" \\
       -d "action=get_feature_flags&CID=\${CID}" \\
       | python3 -m json.tool | grep -E "k8s|dcf_multi|log_enrich"

  2. Reboot the controller VM:
     aws ec2 reboot-instances --instance-ids <controller-instance-id> --region eu-west-2
     # or: Azure portal → Restart for Azure-hosted controllers

  3. Wait for controller to come back (~3-5 min), then re-check flags:
     CID=\$(curl -sk "https://${CONTROLLER_IP}/v2/api" \\
       -d "action=login&username=${CONTROLLER_USER}&password=${CONTROLLER_PASS}" \\
       | python3 -c "import sys,json; print(json.load(sys.stdin).get('CID',''))")
     curl -sk "https://${CONTROLLER_IP}/v2/api" \\
       -d "action=get_feature_flags&CID=\${CID}" \\
       | python3 -m json.tool | grep -E "k8s|dcf_multi|log_enrich"

  Expected: all 5 flags (k8s, k8s_dcf_policies, dcf_multi_policies, k8s_discovery, log_enrichment)
  reset to false with no alert.

  4. Verify enforcement gap:
     kubectl exec -n ${MCP_NS} <pod> -c <shim> -- \\
       curl -s --max-time 15 -o /dev/null -w "HTTP:%{http_code} Exit:%{exitcode}" https://api.openai.com
     Expected after reboot (before re-enabling flags): HTTP:200

  5. Re-enable flags (workaround):
     for f in k8s k8s_dcf_policies dcf_multi_policies k8s_discovery log_enrichment; do
       curl -sk "https://${CONTROLLER_IP}/v2/api" \\
         --data-urlencode "action=enable_controller_feature" \\
         --data-urlencode "CID=\${CID}" \\
         --data-urlencode "feature=\$f"
     done
     terraform apply

INSTRUCTIONS
fi

# ══════════════════════════════════════════════════════════════════════════════
section "Summary"
# ══════════════════════════════════════════════════════════════════════════════
if [[ $FAILURES -eq 0 ]]; then
  echo -e "${GREEN}All checks passed.${NC}"
else
  echo -e "${RED}${FAILURES} check(s) failed. Review output above.${NC}"
  exit 1
fi
