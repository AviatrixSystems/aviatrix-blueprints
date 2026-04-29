---
name: qa-blueprint
description: AI-QA an Aviatrix blueprint by deploying it as a customer using only the README, capturing UX gaps, and opening a fix PR. Replaces test-blueprint.
argument-hint: <blueprint-name> [--dry-run]
disable-model-invocation: true
allowed-tools:
  - Bash(terraform *)
  - Bash(az *)
  - Bash(aws *)
  - Bash(gcloud *)
  - Bash(kubectl *)
  - Bash(helm *)
  - Bash(curl *)
  - Bash(gh *)
  - Bash(git *)
  - Bash(ls *)
  - Bash(cp *)
  - Bash(mkdir *)
  - Bash(rm *)
  - Bash(grep *)
  - Bash(awk *)
  - Bash(sed *)
  - Bash(python3 *)
  - Bash(jq *)
  - Bash(source *)
  - Bash(test *)
  - Read
  - Edit
  - Write
  - Glob
  - Grep
---

# QA Blueprint

AI-QA an Aviatrix blueprint by deploying it as a customer using only the README. Captures UX gaps that surface during the run (copy-paste failures, stale values, README↔code mismatches, missing prereqs), applies fixes, and opens a PR.

This skill replaces `/test-blueprint`. The difference is mindset: `test-blueprint` asked "does it work?"; `qa-blueprint` asks "does it work *for a customer reading only the README?*". The README is the agent's only source of truth for *what to do* during the run.

## Usage

```
/qa-blueprint <blueprint-name> [--dry-run]
```

- `<blueprint-name>` — directory under `blueprints/` (e.g., `azure-aks-multicluster`). Multi-cloud blueprints with `aws/`, `azure/`, `gcp/` subdirs require the cloud subpath (e.g., `k8s-cluster-aas/aws`).
- `--dry-run` — parse the README and print the phase plan without deploying. Useful for verifying the skill itself.

One pass per invocation. Each pass produces one PR with all fixes from that run.

## Prerequisites

Before invoking the skill, verify the following are set up:

- **`$AVIATRIX_ENV_FILE` exported** — typically in `~/.zshenv`. Default is `~/Documents/Scripting/chris-avx-lab/controller_env_ga.sh`. Override with any path containing `AVIATRIX_CONTROLLER_IP` / `AVIATRIX_USERNAME` / `AVIATRIX_PASSWORD` exports.
- **Cloud CLI(s) logged in** for whatever the blueprint targets:
  - Azure → `az account show` returns the right subscription
  - AWS → `aws sts get-caller-identity` works
  - GCP → `gcloud auth list` shows an active account
- **`gh` authenticated** — `gh auth status` returns logged in. Required for opening the PR at the end.
- **Sufficient cloud quota** for whatever the blueprint deploys. The skill will run any pre-flight quota checks documented in the README, but if those checks aren't there you're on your own to verify quotas in advance.

## What this skill does NOT do

- It does not auto-merge the PR. Merging is a human decision.
- It does not loop. One pass per invocation; rerun if you want another pass after merging.
- It does not split fixes into multiple PRs. All gap fixes from one run land in one PR.
- It does not skip git hooks (`--no-verify` is never used).
- It does not auto-handle Playwright/UI verification (text-based checks only in v1).
