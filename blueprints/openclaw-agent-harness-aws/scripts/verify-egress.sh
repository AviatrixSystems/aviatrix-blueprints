#!/usr/bin/env bash
set -euo pipefail

POLICY_MODE="${POLICY_MODE:-monitor}"

cat <<INFO
Aviatrix egress smoke test
Policy mode assumption: ${POLICY_MODE}

Expected behavior:
- monitor: denied/default destinations still connect but are logged under the deny/default rules.
- enforce: denied/default destinations fail and are logged as DENY.
INFO

urls=(
  "https://openclaw.ai"
  "https://docs.openclaw.ai"
  "https://clawhub.ai"
  "https://integrate.api.nvidia.com"
  "https://inference-api.nvidia.com"
  "https://registry.npmjs.org"
  "https://github.com"
  "https://api.openai.com"
  "https://api.anthropic.com"
  "https://example.invalid"
)

for url in "${urls[@]}"; do
  echo
  echo "==> ${url}"
  if timeout 12 curl -sSIL "${url}" | sed -n '1,6p'; then
    echo "result=connected"
  else
    echo "result=blocked-or-unreachable"
  fi
done

echo
echo "==> VPC DNS resolver path: getent hosts openclaw.ai"
getent hosts openclaw.ai || true

echo
echo "==> external DNS exfil path: dig @1.1.1.1 openclaw.ai"
if command -v dig >/dev/null 2>&1; then
  timeout 6 dig @1.1.1.1 openclaw.ai A +short || true
else
  echo "dig not installed; install dnsutils or bind-utils to test UDP/53."
fi
