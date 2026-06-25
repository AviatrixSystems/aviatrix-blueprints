#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform is not installed. Install Terraform/OpenTofu to run fmt/init/validate." >&2
  exit 2
fi

terraform fmt -check -recursive
terraform init -backend=false
terraform validate

echo "Preflight passed."
