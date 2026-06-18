#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Aviatrix Blueprints — Local Terraform Deploy
#
# Orchestrates multi-layer Terraform deployments locally.
# Reads configuration from CFG_* environment variables.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

# ── Helpers ──
ok()     { echo "✓ $*"; }
warn()   { echo "! $*"; }
err()    { echo "✗ $*" >&2; }
info()   { echo "▸ $*"; }
header() { echo ""; echo "═══ $* ═══"; echo ""; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Read config ──
PATTERN="${CFG_PATTERN:?Pattern is required}"
CSP="${CFG_CSP:?CSP is required}"
ACTION="${CFG_ACTION:?Action is required}"
LAYER="${CFG_LAYER:?Layer is required}"

AVIATRIX_CONTROLLER="${CFG_AVIATRIX_CONTROLLER:?Controller IP is required}"
AVIATRIX_USER="${CFG_AVIATRIX_USER:-admin}"
AVIATRIX_PASS="${CFG_AVIATRIX_PASS:?Password is required}"

export AVIATRIX_CONTROLLER_IP="$AVIATRIX_CONTROLLER"
export AVIATRIX_USERNAME="$AVIATRIX_USER"
export AVIATRIX_PASSWORD="$AVIATRIX_PASS"

# Set TF_VAR for Aviatrix account names (both patterns use different var names)
if [ -n "${CFG_AVX_AWS_ACCOUNT:-}" ]; then
  export TF_VAR_aviatrix_aws_account_name="$CFG_AVX_AWS_ACCOUNT"
  export TF_VAR_aws_account_name="$CFG_AVX_AWS_ACCOUNT"
fi
if [ -n "${CFG_AVX_AZURE_ACCOUNT:-}" ]; then
  export TF_VAR_aviatrix_azure_account_name="$CFG_AVX_AZURE_ACCOUNT"
fi
if [ -n "${CFG_AVX_GCP_ACCOUNT:-}" ]; then
  export TF_VAR_aviatrix_gcp_account_name="$CFG_AVX_GCP_ACCOUNT"
fi

BASE_DIR="${REPO_ROOT}/${PATTERN}/${CSP}"

# ── Prerequisite checks ──
check_tool() {
  if ! command -v "$1" &>/dev/null; then
    err "Required tool not found: $1"
    return 1
  fi
}

prereq_ok=0
check_tool terraform || prereq_ok=1
check_tool kubectl   || prereq_ok=1

case "$CSP" in
  aws*)  check_tool aws   || prereq_ok=1 ;;
  azure) check_tool az    || prereq_ok=1 ;;
  gcp)   check_tool gcloud || prereq_ok=1 ;;
esac

if [ "$prereq_ok" -ne 0 ]; then
  err "Missing prerequisites — install the tools listed above and retry."
  exit 1
fi
ok "All prerequisite tools found"

# ── Compute matrix targets ──
case "$PATTERN" in
  cluster-aas)         TARGETS=(team-a team-b team-c) ;;
  namespace-aas)       TARGETS=(shared) ;;
  prod-nonprod-hybrid) TARGETS=(prod nonprod) ;;
  *)                   err "Unknown pattern: $PATTERN"; exit 1 ;;
esac

header "Deploy Configuration"
info "Pattern:    ${PATTERN}"
info "CSP:        ${CSP}"
info "Action:     ${ACTION}"
info "Layer:      ${LAYER}"
info "Targets:    ${TARGETS[*]}"
info "Base dir:   ${BASE_DIR}"

# ── Terraform helpers ──
tf_run() {
  local dir="$1" action="$2" label="$3"
  info "Running ${action} in ${label}..."

  if [ ! -d "$dir" ]; then
    warn "Directory not found: $dir — skipping"
    return 0
  fi

  terraform -chdir="$dir" init -input=false -no-color

  local logfile
  logfile="$(mktemp)"

  case "$action" in
    plan)
      terraform -chdir="$dir" plan -no-color
      ;;
    apply)
      local exit_code=0
      terraform -chdir="$dir" plan -no-color -out=tfplan
      terraform -chdir="$dir" apply -auto-approve tfplan 2>&1 | tee "$logfile" || exit_code=$?
      rm -f "${dir}/tfplan"

      if [ "$exit_code" -ne 0 ]; then
        # Check if the failure is an "already exists" error that may resolve on retry
        if grep -q 'already exists\|AVXERR-SMARTGROUP-0004\|AVXERR-TOOLS-0031\|alreadyExists' "$logfile"; then
          warn "${label}: resources already exist — retrying apply to converge state..."
          terraform -chdir="$dir" apply -auto-approve -no-color
          exit_code=$?
        fi
      fi

      rm -f "$logfile"
      if [ "$exit_code" -ne 0 ]; then
        err "${label} apply failed"
        return "$exit_code"
      fi
      ;;
    destroy)
      terraform -chdir="$dir" destroy -auto-approve -no-color
      ;;
  esac

  ok "${label} ${action} complete"
}

# ── Deploy layers (forward order) ──
run_deploy() {
  # Layer 1: Network
  if [[ "$LAYER" == "all" || "$LAYER" == "network" ]]; then
    header "Layer 1: Network"
    tf_run "${BASE_DIR}/network" "$ACTION" "Network"
  fi

  # Layer 2: Clusters (parallel)
  if [[ "$LAYER" == "all" || "$LAYER" == "clusters" ]]; then
    header "Layer 2: Clusters"
    local pids=()
    for target in "${TARGETS[@]}"; do
      (tf_run "${BASE_DIR}/clusters/${target}" "$ACTION" "Cluster ${target}") &
      pids+=($!)
    done
    local failed=0
    for pid in "${pids[@]}"; do
      if ! wait "$pid"; then
        failed=1
      fi
    done
    if [ "$failed" -eq 1 ]; then
      err "One or more cluster deployments failed"
      exit 1
    fi
  fi

  # Layer 3: Nodes (parallel)
  if [[ "$LAYER" == "all" || "$LAYER" == "nodes" ]]; then
    header "Layer 3: Nodes"
    local pids=()
    for target in "${TARGETS[@]}"; do
      (tf_run "${BASE_DIR}/nodes/${target}" "$ACTION" "Nodes ${target}") &
      pids+=($!)
    done
    local failed=0
    for pid in "${pids[@]}"; do
      if ! wait "$pid"; then
        failed=1
      fi
    done
    if [ "$failed" -eq 1 ]; then
      err "One or more node deployments failed"
      exit 1
    fi
  fi

  # Layer 4: CRDs (kubectl apply)
  if [[ "$LAYER" == "all" || "$LAYER" == "crds" ]]; then
    local crds_dir="${BASE_DIR}/k8s-apps/dcf-crd"
    if [ -d "$crds_dir" ]; then
      header "Layer 4: CRDs"

      # Refresh kubeconfig for each target cluster before applying CRDs
      local region="${AWS_DEFAULT_REGION:-us-east-2}"
      for target in "${TARGETS[@]}"; do
        local cluster_dir="${BASE_DIR}/clusters/${target}"
        if [ -d "$cluster_dir" ] && [ -f "$cluster_dir/terraform.tfstate" ]; then
          local cluster_name
          cluster_name=$(terraform -chdir="$cluster_dir" output -raw cluster_name 2>/dev/null || echo "")
          if [ -n "$cluster_name" ]; then
            info "Updating kubeconfig for ${cluster_name}..."
            aws eks update-kubeconfig --name "$cluster_name" --region "$region" --alias "$cluster_name" 2>/dev/null \
              && ok "kubeconfig updated for ${cluster_name}" \
              || warn "Could not update kubeconfig for ${cluster_name}"
          fi
        fi
      done

      info "Applying Kubernetes manifests from ${crds_dir}..."
      for f in "${crds_dir}"/*.yaml; do
        [ -f "$f" ] || continue
        info "kubectl apply -f $(basename "$f")"
        kubectl apply -f "$f" --validate=false
        ok "Applied $(basename "$f")"
      done
    else
      info "No CRDs directory found — skipping Layer 4"
    fi
  fi
}

# ── Destroy layers (reverse order) ──
run_destroy() {
  # Layer 4: CRDs
  if [[ "$LAYER" == "all" || "$LAYER" == "crds" ]]; then
    local crds_dir="${BASE_DIR}/k8s-apps/dcf-crd"
    if [ -d "$crds_dir" ]; then
      header "Layer 4: CRDs (destroy)"
      kubectl delete -f "$crds_dir" --ignore-not-found 2>/dev/null || true
      ok "CRDs removed"
    fi
  fi

  # Layer 3: Nodes (parallel)
  if [[ "$LAYER" == "all" || "$LAYER" == "nodes" ]]; then
    header "Layer 3: Nodes (destroy)"
    local pids=()
    for target in "${TARGETS[@]}"; do
      (tf_run "${BASE_DIR}/nodes/${target}" "destroy" "Nodes ${target}") &
      pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "$pid" || true; done
  fi

  # Layer 2: Clusters (parallel)
  if [[ "$LAYER" == "all" || "$LAYER" == "clusters" ]]; then
    header "Layer 2: Clusters (destroy)"
    local pids=()
    for target in "${TARGETS[@]}"; do
      (tf_run "${BASE_DIR}/clusters/${target}" "destroy" "Cluster ${target}") &
      pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "$pid" || true; done
  fi

  # Layer 1: Network
  if [[ "$LAYER" == "all" || "$LAYER" == "network" ]]; then
    header "Layer 1: Network (destroy)"
    tf_run "${BASE_DIR}/network" "destroy" "Network"
  fi
}

# ── Main ──
if [[ "$ACTION" == "destroy" ]]; then
  run_destroy
else
  run_deploy
fi

header "Done"
ok "${ACTION} completed for ${PATTERN}/${CSP} (layer: ${LAYER})"
