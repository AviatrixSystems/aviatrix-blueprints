#!/usr/bin/env bash
# Idempotently pulls the active Aviatrix DCF MITM CA from the controller and
# writes it to ./avx-root-ca.pem in the blueprint dir. Safe to re-run; it
# refreshes on rotation (/v2.5/api/dcf/mitm-ca/{ca_id}/regenerate).
#
# Requires: AVIATRIX_CONTROLLER_IP, AVIATRIX_USERNAME, AVIATRIX_PASSWORD env
# vars (or pass via the CLI). Uses the v2 login to obtain a CID, then the
# v2.5 /dcf/mitm-ca endpoint with `Authorization: cid <token>`.
set -euo pipefail

CTRL="${AVIATRIX_CONTROLLER_IP:-${1:-}}"
USER="${AVIATRIX_USERNAME:-admin}"
PW="${AVIATRIX_PASSWORD:-}"

if [[ -z "${CTRL}" || -z "${PW}" ]]; then
  echo "usage: AVIATRIX_CONTROLLER_IP=... AVIATRIX_USERNAME=admin AVIATRIX_PASSWORD=... $0" >&2
  exit 64
fi

BLUEPRINT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${BLUEPRINT_DIR}/avx-root-ca.pem"

CID="$(curl -sk -X POST "https://${CTRL}/v2/api" \
  --data-urlencode "action=login" \
  --data-urlencode "username=${USER}" \
  --data-urlencode "password=${PW}" | jq -r '.CID')"

if [[ -z "${CID}" || "${CID}" == "null" ]]; then
  echo "login failed" >&2
  exit 1
fi

RESP="$(curl -sk "https://${CTRL}/v2.5/api/dcf/mitm-ca" \
  -H "Authorization: cid ${CID}" \
  -H "Accept: application/json")"

PEM="$(echo "${RESP}" | jq -r '.cas[] | select(.state == "active") | .certificate_chain')"
CA_ID="$(echo "${RESP}" | jq -r '.cas[] | select(.state == "active") | .ca_id')"
NAME="$(echo "${RESP}" | jq -r '.cas[] | select(.state == "active") | .name')"

if [[ -z "${PEM}" || "${PEM}" == "null" ]]; then
  echo "no active MITM CA on controller - upload or regenerate first" >&2
  echo "raw response: ${RESP}" >&2
  exit 2
fi

printf '%s' "${PEM}" > "${OUT}"
# Also drop a copy into the Dockerfile build context so image rebuilds
# pick it up automatically.
cp -f "${OUT}" "${BLUEPRINT_DIR}/agent/avx-root-ca.pem"

echo "wrote ${OUT}"
echo "wrote ${BLUEPRINT_DIR}/agent/avx-root-ca.pem"
echo "  ca_id:  ${CA_ID}"
echo "  name:   ${NAME}"
openssl x509 -in "${OUT}" -noout -subject -startdate -enddate -sha1 -fingerprint 2>/dev/null || true
