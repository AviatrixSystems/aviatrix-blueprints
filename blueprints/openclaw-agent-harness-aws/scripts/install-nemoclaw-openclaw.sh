#!/usr/bin/env bash
set -euo pipefail

cat <<'HELP'
Runs the NVIDIA NemoClaw installer for OpenClaw.
For unattended/CI use, export the documented variables first, for example:
  export NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1
  export NEMOCLAW_NON_INTERACTIVE=1
  export NEMOCLAW_PROVIDER=nvidia
  export NEMOCLAW_API_KEY=<secret>
HELP

curl -fsSL https://www.nvidia.com/nemoclaw.sh -o /tmp/nemoclaw.sh
bash /tmp/nemoclaw.sh
