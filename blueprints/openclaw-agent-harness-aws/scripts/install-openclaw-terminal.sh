#!/usr/bin/env bash
set -euo pipefail

# Installs OpenClaw CLI without the interactive onboarding flow.
# After install, run: openclaw onboard --install-daemon
curl -fsSL https://openclaw.ai/install.sh -o /tmp/openclaw-install.sh
bash /tmp/openclaw-install.sh --no-onboard
