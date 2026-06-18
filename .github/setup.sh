#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Aviatrix Blueprints — GitHub Actions Environment Setup
#
# This script automates the one-time setup required before
# running the deploy workflow. It will:
#
#   1. Check prerequisites (CLI tools)
#   2. Bootstrap S3 state bucket via Terraform
#   3. Configure GitHub repository secrets & variables
#   4. Create GitHub environments with protection rules
#
# Usage:
#   cd blueprints/.github
#   chmod +x setup.sh
#   ./setup.sh
#
# Requires: aws, gh, terraform, jq
# ─────────────────────────────────────────────────────────────
set -euo pipefail

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}▸${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}!${NC} $*"; }
err()   { echo -e "${RED}✗${NC} $*" >&2; }
header() { echo -e "\n${BOLD}═══ $* ═══${NC}\n"; }

# ── Resolve script and repo directories ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="${SCRIPT_DIR}/bootstrap"

# ─────────────────────────────────────────────────────────────
# Step 0: Prerequisite checks
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
  echo ""
  err "Missing tools: ${MISSING[*]}"
  echo "  Install them before running this script:"
  echo "    brew install awscli gh terraform jq"
  exit 1
fi

# Check AWS authentication
if ! aws sts get-caller-identity &>/dev/null; then
  err "AWS credentials not configured. Run 'aws sso login' or export AWS keys."
  exit 1
fi
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
ok "AWS authenticated (account: ${AWS_ACCOUNT_ID})"

# Check GitHub CLI authentication
if ! gh auth status &>/dev/null 2>&1; then
  err "GitHub CLI not authenticated. Run 'gh auth login'."
  exit 1
fi
ok "GitHub CLI authenticated"

# Detect repository
if REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null); then
  ok "Repository: ${REPO}"
else
  err "Not inside a GitHub repository. Run this from the repo root or a subdirectory."
  exit 1
fi

# ─────────────────────────────────────────────────────────────
# Step 1: Collect configuration
# ─────────────────────────────────────────────────────────────
header "Configuration"

prompt() {
  local var_name="$1" prompt_text="$2" default="${3:-}"
  local value
  if [ -n "$default" ]; then
    read -rp "$(echo -e "${CYAN}▸${NC}") ${prompt_text} [${default}]: " value
    value="${value:-$default}"
  else
    while [ -z "${value:-}" ]; do
      read -rp "$(echo -e "${CYAN}▸${NC}") ${prompt_text}: " value
      [ -z "$value" ] && warn "This field is required."
    done
  fi
  eval "$var_name='$value'"
}

prompt_secret() {
  local var_name="$1" prompt_text="$2"
  local value
  while [ -z "${value:-}" ]; do
    read -srp "$(echo -e "${CYAN}▸${NC}") ${prompt_text}: " value
    echo ""
    [ -z "$value" ] && warn "This field is required."
  done
  eval "$var_name='$value'"
}

echo "Enter the values for your deployment. Press Enter to accept defaults."
echo ""

prompt AWS_REGION          "AWS region"                          "us-east-2"
prompt AVIATRIX_CONTROLLER "Aviatrix controller IP"              ""
prompt AVIATRIX_USER       "Aviatrix username"                   "admin"
prompt_secret AVIATRIX_PASS "Aviatrix password"
prompt AVX_AWS_ACCOUNT     "Aviatrix-onboarded AWS account name" "lab-test-aws"
prompt AWS_ROLE_ARN_INPUT  "IAM role ARN for GitHub OIDC"        ""

echo ""
info "Optional: Azure and GCP credentials (press Enter to skip)"
read -rp "$(echo -e "${CYAN}▸${NC}") Configure Azure? (y/N): " SETUP_AZURE
read -rp "$(echo -e "${CYAN}▸${NC}") Configure GCP? (y/N): " SETUP_GCP

AZURE_CREDS=""
GCP_CREDS=""
AVX_AZURE_ACCOUNT=""
AVX_GCP_ACCOUNT=""

if [[ "${SETUP_AZURE}" =~ ^[Yy]$ ]]; then
  prompt_secret AZURE_CREDS      "Azure credentials JSON (single line)"
  prompt AVX_AZURE_ACCOUNT       "Aviatrix-onboarded Azure account name" ""
fi

if [[ "${SETUP_GCP}" =~ ^[Yy]$ ]]; then
  prompt_secret GCP_CREDS        "GCP credentials JSON (single line)"
  prompt AVX_GCP_ACCOUNT         "Aviatrix-onboarded GCP account name" ""
fi

# ─────────────────────────────────────────────────────────────
# Step 2: Bootstrap S3 state bucket
# ─────────────────────────────────────────────────────────────
header "Bootstrapping S3 state bucket"

if [ ! -d "$BOOTSTRAP_DIR" ]; then
  err "Bootstrap directory not found at ${BOOTSTRAP_DIR}"
  exit 1
fi

cd "$BOOTSTRAP_DIR"

# Check if already bootstrapped
TF_STATE_BUCKET=""
if [ -f terraform.tfstate ]; then
  EXISTING_BUCKET=$(terraform output -raw bucket_name 2>/dev/null || echo "")
  if [ -n "$EXISTING_BUCKET" ]; then
    # Verify bucket actually exists
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

# ─────────────────────────────────────────────────────────────
# Step 3: Configure GitHub secrets
# ─────────────────────────────────────────────────────────────
header "Configuring GitHub secrets"

set_secret() {
  local name="$1" value="$2"
  if [ -n "$value" ]; then
    echo "$value" | gh secret set "$name" --repo "$REPO" 2>/dev/null
    ok "Secret: ${name}"
  fi
}

set_secret "AVIATRIX_CONTROLLER_IP"  "$AVIATRIX_CONTROLLER"
set_secret "AVIATRIX_USERNAME"       "$AVIATRIX_USER"
set_secret "AVIATRIX_PASSWORD"       "$AVIATRIX_PASS"
set_secret "AWS_ROLE_ARN"            "$AWS_ROLE_ARN_INPUT"
set_secret "AWS_ACCOUNT_ID"          "$AWS_ACCOUNT_ID"
set_secret "AVIATRIX_AWS_ACCOUNT"    "$AVX_AWS_ACCOUNT"

if [ -n "$AZURE_CREDS" ]; then
  set_secret "AZURE_CREDENTIALS"      "$AZURE_CREDS"
  set_secret "AVIATRIX_AZURE_ACCOUNT" "$AVX_AZURE_ACCOUNT"
fi

if [ -n "$GCP_CREDS" ]; then
  set_secret "GCP_CREDENTIALS"        "$GCP_CREDS"
  set_secret "AVIATRIX_GCP_ACCOUNT"   "$AVX_GCP_ACCOUNT"
fi

# ─────────────────────────────────────────────────────────────
# Step 4: Configure GitHub variables
# ─────────────────────────────────────────────────────────────
header "Configuring GitHub variables"

set_variable() {
  local name="$1" value="$2"
  # gh variable set creates or updates
  gh variable set "$name" --repo "$REPO" --body "$value" 2>/dev/null
  ok "Variable: ${name} = ${value}"
}

set_variable "AWS_REGION"       "$AWS_REGION"
set_variable "TF_STATE_BUCKET"  "$TF_STATE_BUCKET"

# ─────────────────────────────────────────────────────────────
# Step 5: Create GitHub environments
# ─────────────────────────────────────────────────────────────
header "Creating GitHub environments"

create_environment() {
  local env_name="$1"
  # Create environment via API (gh env commands don't exist)
  gh api "repos/${REPO}/environments/${env_name}" \
    --method PUT \
    --input /dev/null \
    &>/dev/null && ok "Environment: ${env_name}" \
    || warn "Could not create environment '${env_name}' — create it manually in Settings > Environments"
}

create_environment "production"
create_environment "destroy"

warn "Add required reviewers to environments manually:"
echo "  Go to: https://github.com/${REPO}/settings/environments"
echo "  - production: add 1+ reviewer(s) for apply"
echo "  - destroy:    add 2+ reviewer(s) for destroy"

# ─────────────────────────────────────────────────────────────
# Step 6: Verify OIDC provider
# ─────────────────────────────────────────────────────────────
header "Checking AWS OIDC provider"

OIDC_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" &>/dev/null; then
  ok "GitHub OIDC provider exists"
else
  warn "GitHub OIDC provider not found in AWS account ${AWS_ACCOUNT_ID}"
  echo ""
  echo "  Create it with:"
  echo "    aws iam create-open-id-connect-provider \\"
  echo "      --url https://token.actions.githubusercontent.com \\"
  echo "      --client-id-list sts.amazonaws.com \\"
  echo "      --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1"
  echo ""
fi

# ─────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────
header "Setup complete"

cat <<EOF

  ${GREEN}Configuration summary:${NC}

  Repository:       ${REPO}
  AWS Account:      ${AWS_ACCOUNT_ID}
  AWS Region:       ${AWS_REGION}
  State Bucket:     ${TF_STATE_BUCKET}
  Controller:       ${AVIATRIX_CONTROLLER}
  OIDC Role:        ${AWS_ROLE_ARN_INPUT}

  ${BOLD}Remaining manual steps:${NC}

  1. Add required reviewers to GitHub environments:
     https://github.com/${REPO}/settings/environments

  2. Verify the OIDC IAM role trust policy allows:
     repo:${REPO}:*

  3. Run your first deployment:
     Go to Actions > Deploy Aviatrix K8s Blueprints > Run workflow
       Pattern: prod-nonprod-hybrid
       CSP:     aws
       Action:  plan
       Layer:   all

EOF
