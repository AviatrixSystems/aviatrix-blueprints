#!/usr/bin/env bash
#
# DCF Traffic Test Runner
# Validates Aviatrix Distributed Cloud Firewall rules across EKS clusters.
#
# Usage:
#   ./run-tests.sh [TEAM_A_CTX] [TEAM_B_CTX] [TEAM_C_CTX]
#
# Defaults to contexts: caas-4462-team-a, caas-4462-team-b, caas-4462-team-c
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Cluster contexts
# ---------------------------------------------------------------------------
CTX_A="${1:-caas-4462-team-a}"
CTX_B="${2:-caas-4462-team-b}"
CTX_C="${3:-caas-4462-team-c}"

NAMESPACE="traffic-test"
POD_NAME="netshoot"
CURL_TIMEOUT=10          # seconds — long enough for DCF-permitted flows
DNS_WAIT_ATTEMPTS=30     # ~5 min with 10s intervals
DNS_WAIT_INTERVAL=10

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
TOTAL=0
PASSED=0
FAILED=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERR]${NC}   $*"; }

wait_for_dns() {
  local hostname="$1"
  log "Waiting for DNS resolution of ${hostname} ..."
  for ((i=1; i<=DNS_WAIT_ATTEMPTS; i++)); do
    if host "$hostname" &>/dev/null || nslookup "$hostname" &>/dev/null; then
      log "DNS resolved: ${hostname}"
      return 0
    fi
    log "  attempt ${i}/${DNS_WAIT_ATTEMPTS} — retrying in ${DNS_WAIT_INTERVAL}s"
    sleep "$DNS_WAIT_INTERVAL"
  done
  warn "DNS did not resolve for ${hostname} after ${DNS_WAIT_ATTEMPTS} attempts — tests may fail"
  return 1
}

wait_for_pod() {
  local ctx="$1"
  log "Waiting for pod ${POD_NAME} in ${ctx} to be Running ..."
  kubectl --context "$ctx" -n "$NAMESPACE" wait pod/"$POD_NAME" \
    --for=condition=Ready --timeout=120s
}

# ---------------------------------------------------------------------------
# run_test <label> <context> <curl_args...> <expect: PASS|FAIL> <dcf_rule>
#
#   PASS = we expect a successful HTTP response (exit 0, HTTP 2xx/3xx)
#   FAIL = we expect a timeout / connection refused / no response
# ---------------------------------------------------------------------------
run_test() {
  local label="$1"; shift
  local ctx="$1"; shift
  local expect="$1"; shift
  local rule="$1"; shift
  local curl_cmd="$*"

  TOTAL=$((TOTAL + 1))

  echo ""
  echo -e "${BOLD}--- ${label} ---${NC}"
  echo -e "  From:     ${ctx}"
  echo -e "  Command:  curl ${curl_cmd}"
  echo -e "  Expected: ${expect} (${rule})"

  local output exit_code http_code
  output=$(kubectl --context "$ctx" -n "$NAMESPACE" exec "$POD_NAME" -- \
    curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT" $curl_cmd 2>&1) || true
  exit_code=$?
  http_code="$output"

  # Determine actual result
  local actual="FAIL"
  if [[ "$http_code" =~ ^[23] ]]; then
    actual="PASS"
  fi

  # Compare
  if [[ "$actual" == "$expect" ]]; then
    echo -e "  Result:   ${GREEN}${actual}${NC} (HTTP ${http_code}) -- ${GREEN}PASS${NC}"
    PASSED=$((PASSED + 1))
  else
    echo -e "  Result:   ${RED}${actual}${NC} (HTTP ${http_code}) -- ${RED}FAIL${NC} (expected ${expect})"
    FAILED=$((FAILED + 1))
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}============================================${NC}"
echo -e "${BOLD}  DCF Traffic Test Suite${NC}"
echo -e "${BOLD}============================================${NC}"
echo ""
echo -e "  Cluster A: ${CTX_A}"
echo -e "  Cluster B: ${CTX_B}"
echo -e "  Cluster C: ${CTX_C}"
echo ""

# --- Pre-flight: wait for pods ----
log "Checking netshoot pods are ready ..."
wait_for_pod "$CTX_A"
wait_for_pod "$CTX_B"
wait_for_pod "$CTX_C"

# --- Pre-flight: wait for DNS ----
log "Checking DNS propagation ..."
# We run DNS checks from the team-a netshoot pod (inside the VPC)
for host in team-a.aws.aviatrixdemo.local team-b.aws.aviatrixdemo.local team-c.aws.aviatrixdemo.local; do
  for ((i=1; i<=DNS_WAIT_ATTEMPTS; i++)); do
    if kubectl --context "$CTX_A" -n "$NAMESPACE" exec "$POD_NAME" -- \
         nslookup "$host" &>/dev/null; then
      log "DNS resolved (from team-a pod): ${host}"
      break
    fi
    if [[ $i -eq $DNS_WAIT_ATTEMPTS ]]; then
      warn "DNS not resolved for ${host} after ${DNS_WAIT_ATTEMPTS} attempts"
    fi
    sleep "$DNS_WAIT_INTERVAL"
  done
done

# ---------------------------------------------------------------------------
# Test Matrix
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}============================================${NC}"
echo -e "${BOLD}  Running Tests${NC}"
echo -e "${BOLD}============================================${NC}"

# T1: team-a -> team-b:443  (PERMIT rule 110)
run_test "T1: team-a -> team-b:443" "$CTX_A" "PASS" "rule 110 PERMIT" \
  "http://team-b.aws.aviatrixdemo.local:443"

# T2: team-b -> team-a:8080  (PERMIT rule 111)
run_test "T2: team-b -> team-a:8080" "$CTX_B" "PASS" "rule 111 PERMIT" \
  "http://team-a.aws.aviatrixdemo.local:8080"

# T3: team-a -> team-c:443  (DENY rule 120)
run_test "T3: team-a -> team-c:443" "$CTX_A" "FAIL" "rule 120 DENY" \
  "http://team-c.aws.aviatrixdemo.local:443"

# T4: team-c -> team-a:8080  (DENY rule 121)
run_test "T4: team-c -> team-a:8080" "$CTX_C" "FAIL" "rule 121 DENY" \
  "http://team-a.aws.aviatrixdemo.local:8080"

# T5: team-b -> team-c:443  (DENY rule 122)
run_test "T5: team-b -> team-c:443" "$CTX_B" "FAIL" "rule 122 DENY" \
  "http://team-c.aws.aviatrixdemo.local:443"

# T6: team-c -> team-b:443  (DENY rule 123)
run_test "T6: team-c -> team-b:443" "$CTX_C" "FAIL" "rule 123 DENY" \
  "http://team-b.aws.aviatrixdemo.local:443"

# T7: team-a -> public internet (registry.k8s.io) (PERMIT rule 150)
run_test "T7: team-a -> registry.k8s.io (egress)" "$CTX_A" "PASS" "rule 150 PERMIT egress" \
  "https://registry.k8s.io"

# T8: team-a -> example.com  (no egress rule — blocked)
run_test "T8: team-a -> example.com (no egress rule)" "$CTX_A" "FAIL" "no matching egress rule" \
  "https://example.com"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}============================================${NC}"
echo -e "${BOLD}  Summary${NC}"
echo -e "${BOLD}============================================${NC}"
echo ""
echo -e "  Total:  ${TOTAL}"
echo -e "  Passed: ${GREEN}${PASSED}${NC}"
echo -e "  Failed: ${RED}${FAILED}${NC}"
echo ""

if [[ $FAILED -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}ALL TESTS PASSED${NC}"
else
  echo -e "  ${RED}${BOLD}${FAILED} TEST(S) FAILED${NC}"
fi

echo ""
exit "$FAILED"
