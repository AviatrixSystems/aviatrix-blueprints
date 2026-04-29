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

## Customer-Mindset Rules (the prime directive)

**During Phases 1–5 (parse, pre-flight, deploy, test, destroy), the README is the only source of truth for what to do.** Project memory, prior conversation context, codebase reading, controller API queries — these are off-limits for *deciding the next action*. They remain available *for verifying* whether the README's claims hold.

### Concrete rules

- **README is silent → log a gap, pick the simplest interpretation, continue.** Don't fail the run on ambiguity; document it. Example: README says `cp tfvars.example tfvars` without specifying which variables to fill — pick defaults from example file comments, log "README doesn't specify required vs optional vars".

- **README says X, code says Y → log a gap, follow the README first.** The README is what a customer reads; code is what insiders read. Example: README says context name is `frontend`; `terraform output kubectl_config_command` returns no `--context`. Run the README's manual `az aks get-credentials … --context frontend` block, log the mismatch.

- **A documented command fails → log the failure verbatim, retry once if it looks transient, then either pragmatic-workaround + continue or abort the phase.** The workaround proves the gap fix. Example: `kubectl apply -f webgrouppolicy-dev.yaml` fails with `namespaces "dev" not found` → log gap, run `kubectl create namespace dev`, retry the apply, continue.

- **Insider knowledge is for verification only.** `terraform state list`, `az resource list`, controller API queries, etc. — fine for *checking* whether a documented behavior actually happened. Not for *deciding what step to do next* — that's always the README's job.

- **Memory cross-checks are diagnostic, not corrective.** If memory says "this controller version always fails step X with error Y", the agent still runs step X exactly as documented, observes the failure, logs the gap. The point is to verify the README accommodates that failure path; pre-empting it would mask the gap.

### Gap categories

| Category | Example |
|---|---|
| copy-paste-failure | Missing `kubectl create namespace`, `${ENV_VAR}` left unexpanded in tfvars instructions |
| stale-value | Threat IP rotated out of feed, version bump needed |
| readme-code-mismatch | tf output missing `--context`, wrong subnet name |
| unstated-prereq | Step Y depends on X but X is in a separate non-obvious section |
| wrong-expected-output | "Health: Healthy" claimed at a step where probe is still failing |
| missing-recovery | Documented step fails reliably; recovery exists but is buried in a callout |
| ambiguous-wording | "your IP" vs "controller IP" vs "client IP" used inconsistently |

### What is NOT a gap (do not log these)

- Personal style/formatting preferences
- Refactoring opportunities not customer-visible
- Issues already addressed by an open PR or a recent commit (`git log --since="7 days ago" -- <file>` covers it)
