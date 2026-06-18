#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Aviatrix Blueprints — Headless Setup (called by setup_gui.py)
#
# Reads configuration from CFG_* environment variables instead
# of interactive prompts. Same logic as setup.sh.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

# ── Helpers ──
ok()    { echo "✓ $*"; }
warn()  { echo "! $*"; }
err()   { echo "✗ $*" >&2; }
info()  { echo "▸ $*"; }
header() { echo ""; echo "═══ $* ═══"; echo ""; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="${SCRIPT_DIR}/bootstrap"

# ─────────────────────────────────────────────────────────────
# Step 0: Prerequisites
# ─────────────────────────────────────────────────────────────
header "Checking prerequisites"

MISSING=()
for cmd in aws gh terraform jq; do
  if command -v "$cmd" &>/dev/null; then
    ok "$cmd $(command -v "$cmd")"
  else
    err "$cmd not found"
    MISSING+=("$cmd")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  err "Missing tools: ${MISSING[*]}"
  exit 1
fi

if ! gh auth status &>/dev/null 2>&1; then
  err "GitHub CLI not authenticated."
  exit 1
fi
ok "GitHub CLI authenticated"

if REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null); then
  ok "Repository: ${REPO}"
else
  err "Not inside a GitHub repository."
  exit 1
fi

# ─────────────────────────────────────────────────────────────
# Step 1: Read config from environment
# ─────────────────────────────────────────────────────────────
header "Configuration"

AVIATRIX_CONTROLLER="${CFG_AVIATRIX_CONTROLLER}"
AVIATRIX_USER="${CFG_AVIATRIX_USER:-admin}"
AVIATRIX_PASS="${CFG_AVIATRIX_PASS}"

SETUP_AWS="${CFG_SETUP_AWS:-n}"
AWS_REGION="${CFG_AWS_REGION:-us-east-2}"
AVX_AWS_ACCOUNT="${CFG_AVX_AWS_ACCOUNT:-lab-test-aws}"
AWS_ROLE_ARN_INPUT="${CFG_AWS_ROLE_ARN:-}"

SETUP_AZURE="${CFG_SETUP_AZURE:-n}"
AZURE_REGION="${CFG_AZURE_REGION:-East US 2}"
AZURE_CREDS="${CFG_AZURE_CREDS:-}"
AVX_AZURE_ACCOUNT="${CFG_AVX_AZURE_ACCOUNT:-}"

SETUP_GCP="${CFG_SETUP_GCP:-n}"
GCP_REGION="${CFG_GCP_REGION:-us-central1}"
GCP_CREDS="${CFG_GCP_CREDS:-}"
AVX_GCP_ACCOUNT="${CFG_AVX_GCP_ACCOUNT:-}"

info "Controller:    ${AVIATRIX_CONTROLLER}"
info "Username:      ${AVIATRIX_USER}"
if [[ "${SETUP_AWS}" =~ ^[Yy]$ ]]; then info "AWS:           enabled (${AWS_REGION})"; fi
if [[ "${SETUP_AZURE}" =~ ^[Yy]$ ]]; then info "Azure:         enabled (${AZURE_REGION})"; fi
if [[ "${SETUP_GCP}" =~ ^[Yy]$ ]]; then info "GCP:           enabled (${GCP_REGION})"; fi

# ─────────────────────────────────────────────────────────────
# Step 2: Bootstrap S3 state bucket (AWS only)
# ─────────────────────────────────────────────────────────────
TF_STATE_BUCKET=""
BOOTSTRAP_MODE="${CFG_BOOTSTRAP_MODE:-local}"

if [[ "${SETUP_AWS}" =~ ^[Yy]$ ]] && [[ "$BOOTSTRAP_MODE" == "remote" ]]; then
  header "Bootstrapping S3 state bucket"

  if [ ! -d "$BOOTSTRAP_DIR" ]; then
    err "Bootstrap directory not found at ${BOOTSTRAP_DIR}"
    exit 1
  fi

  cd "$BOOTSTRAP_DIR"

  if [ -f terraform.tfstate ]; then
    EXISTING_BUCKET=$(terraform output -raw bucket_name 2>/dev/null || echo "")
    if [ -n "$EXISTING_BUCKET" ]; then
      if aws s3api head-bucket --bucket "$EXISTING_BUCKET" &>/dev/null; then
        ok "S3 bucket already exists: ${EXISTING_BUCKET}"
        TF_STATE_BUCKET="$EXISTING_BUCKET"
      fi
    fi
  fi

  if [ -z "$TF_STATE_BUCKET" ]; then
    info "Creating S3 state bucket..."
    terraform init -input=false -no-color
    terraform apply -auto-approve -input=false \
      -var="aws_region=${AWS_REGION}" \
      -no-color
    TF_STATE_BUCKET=$(terraform output -raw bucket_name)
    ok "S3 bucket created: ${TF_STATE_BUCKET}"
  fi

  cd "$SCRIPT_DIR"
elif [[ "${SETUP_AWS}" =~ ^[Yy]$ ]]; then
  header "Skipping S3 bootstrap (local mode)"
  info "Using local Terraform state files. No remote state bucket needed."
fi

# ─────────────────────────────────────────────────────────────
# Steps 3-6: GitHub Actions setup (remote mode only)
# ─────────────────────────────────────────────────────────────
if [[ "$BOOTSTRAP_MODE" == "remote" ]]; then

  header "Configuring GitHub secrets"

  set_secret() {
    local name="$1" value="$2"
    if [ -n "$value" ]; then
      echo "$value" | gh secret set "$name" --repo "$REPO" 2>/dev/null
      ok "Secret: ${name}"
    fi
  }

  # Aviatrix
  set_secret "AVIATRIX_CONTROLLER_IP"  "$AVIATRIX_CONTROLLER"
  set_secret "AVIATRIX_USERNAME"       "$AVIATRIX_USER"
  set_secret "AVIATRIX_PASSWORD"       "$AVIATRIX_PASS"

  # AWS
  if [[ "${SETUP_AWS}" =~ ^[Yy]$ ]]; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null || echo "")
    set_secret "AWS_ROLE_ARN"            "$AWS_ROLE_ARN_INPUT"
    set_secret "AWS_ACCOUNT_ID"          "$AWS_ACCOUNT_ID"
    set_secret "AVIATRIX_AWS_ACCOUNT"    "$AVX_AWS_ACCOUNT"
  fi

  # Azure
  if [[ "${SETUP_AZURE}" =~ ^[Yy]$ ]] && [ -n "$AZURE_CREDS" ]; then
    set_secret "AZURE_CREDENTIALS"      "$AZURE_CREDS"
    set_secret "AVIATRIX_AZURE_ACCOUNT" "$AVX_AZURE_ACCOUNT"
  fi

  # GCP
  if [[ "${SETUP_GCP}" =~ ^[Yy]$ ]] && [ -n "$GCP_CREDS" ]; then
    set_secret "GCP_CREDENTIALS"        "$GCP_CREDS"
    set_secret "AVIATRIX_GCP_ACCOUNT"   "$AVX_GCP_ACCOUNT"
  fi

  header "Configuring GitHub variables"

  set_variable() {
    local name="$1" value="$2"
    gh variable set "$name" --repo "$REPO" --body "$value" 2>/dev/null
    ok "Variable: ${name} = ${value}"
  }

  if [[ "${SETUP_AWS}" =~ ^[Yy]$ ]]; then
    set_variable "AWS_REGION"       "$AWS_REGION"
    [ -n "$TF_STATE_BUCKET" ] && set_variable "TF_STATE_BUCKET"  "$TF_STATE_BUCKET"
  fi

  if [[ "${SETUP_AZURE}" =~ ^[Yy]$ ]]; then
    set_variable "AZURE_REGION"     "$AZURE_REGION"
  fi

  if [[ "${SETUP_GCP}" =~ ^[Yy]$ ]]; then
    set_variable "GCP_REGION"       "$GCP_REGION"
  fi

  header "Creating GitHub environments"

  create_environment() {
    local env_name="$1"
    gh api "repos/${REPO}/environments/${env_name}" \
      --method PUT --input /dev/null &>/dev/null \
      && ok "Environment: ${env_name}" \
      || warn "Could not create environment '${env_name}'"
  }

  create_environment "production"
  create_environment "destroy"

  warn "Add required reviewers manually at:"
  echo "  https://github.com/${REPO}/settings/environments"

  # OIDC provider (AWS only)
  if [[ "${SETUP_AWS}" =~ ^[Yy]$ ]]; then
    header "Checking AWS OIDC provider"

    AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null || echo "")}"
    OIDC_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
    if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" &>/dev/null; then
      ok "GitHub OIDC provider exists"
    else
      warn "GitHub OIDC provider not found — create it manually"
    fi
  fi

fi  # end remote mode

# ─────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────
header "Setup complete"

echo ""
echo "  Mode:             ${BOOTSTRAP_MODE}"
echo "  Repository:       ${REPO}"
echo "  Controller:       ${AVIATRIX_CONTROLLER}"
ENABLED_CSPS=""
if [[ "${SETUP_AWS}" =~ ^[Yy]$ ]]; then
  ENABLED_CSPS="AWS"
  echo "  AWS Region:       ${AWS_REGION}"
  [ -n "$TF_STATE_BUCKET" ] && echo "  State Bucket:     ${TF_STATE_BUCKET}"
  [ -n "$AWS_ROLE_ARN_INPUT" ] && echo "  OIDC Role:        ${AWS_ROLE_ARN_INPUT}"
fi
if [[ "${SETUP_AZURE}" =~ ^[Yy]$ ]]; then
  ENABLED_CSPS="${ENABLED_CSPS:+$ENABLED_CSPS, }Azure"
  echo "  Azure Region:     ${AZURE_REGION}"
fi
if [[ "${SETUP_GCP}" =~ ^[Yy]$ ]]; then
  ENABLED_CSPS="${ENABLED_CSPS:+$ENABLED_CSPS, }GCP"
  echo "  GCP Region:       ${GCP_REGION}"
fi
echo "  Cloud Providers:  ${ENABLED_CSPS:-none}"
echo ""
echo "  Next steps:"
if [[ "$BOOTSTRAP_MODE" == "local" ]]; then
  echo "  1. Export your Aviatrix credentials:"
  echo "     export AVIATRIX_CONTROLLER_IP=\"${AVIATRIX_CONTROLLER}\""
  echo "     export AVIATRIX_USERNAME=\"${AVIATRIX_USER}\""
  echo "     export AVIATRIX_PASSWORD=\"<password>\""
  echo "  2. Navigate to a pattern and deploy:"
  echo "     cd prod-nonprod-hybrid/aws/network"
  echo "     terraform init && terraform apply"
else
  echo "  1. Add reviewers to GitHub environments"
  if [[ "${SETUP_AWS}" =~ ^[Yy]$ ]]; then
    echo "  2. Verify OIDC role trust policy allows: repo:${REPO}:*"
  fi
  echo "  3. Run your first deployment via Actions"
fi
echo ""
