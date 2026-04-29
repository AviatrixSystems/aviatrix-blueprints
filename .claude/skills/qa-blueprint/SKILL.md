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

## Gap-Tracking Format

### Run state directory

All run artifacts live in:

```
/tmp/qa-blueprint-<blueprint-name>-<timestamp>/
├── gaps.md           # accumulating gap log
├── phase-0-bootstrap.log
├── phase-2-preflight.log
├── phase-3-deploy.log
├── phase-4-test.log
├── phase-5-destroy.log
├── phase-6-fix-plan.md
└── report.md         # final report, also used as PR body
```

`<timestamp>` is `date +%Y%m%d-%H%M%S` at run start.

The dir is auto-cleaned at end of a fully successful run; preserved on failure for inspection or resume.

### gaps.md schema

Each gap is a fenced YAML block in `gaps.md`. Append one block per gap as it surfaces.

````yaml
- id: 1
  category: copy-paste-failure
  phase: test-scenario-6
  file: blueprints/azure-aks-multicluster/README.md
  line: 605
  symptom: |
    `kubectl apply -f webgrouppolicy-dev.yaml --context frontend` failed with:
    Error from server (NotFound): namespaces "dev" not found
  expected_per_readme: WebgroupPolicy applied to dev namespace
  actual: namespace dev does not exist; YAML targets it
  workaround_used: kubectl create namespace dev --context frontend
  fix_proposal: |
    Insert `kubectl create namespace dev --context frontend` before the
    webgrouppolicy-dev apply in the Scenario 6 code block. Add a
    one-line note explaining the namespace is not deployed by Terraform.
  files_to_edit:
    - blueprints/azure-aks-multicluster/README.md
````

**Required fields:** `id`, `category`, `phase`, `file`, `symptom`, `fix_proposal`, `files_to_edit`.

**Optional fields:** `line` (when known), `expected_per_readme`, `actual`, `workaround_used`.

`id` is monotonic within the run (1, 2, 3, …). Final report references gaps by these IDs.

### report.md format

Generated at end of run. Used as PR body. Format:

```markdown
# QA run: <blueprint-name>
- Branch: qa/<name>-YYYY-MM-DD-<n>
- Wall-clock: <X>m
- Test scenarios: <P>/<T> pass (<W> worked-around, see gap list)

## Gaps found and fixed (<N>)
- #1 [copy-paste-failure] README.md:605 — missing `kubectl create namespace dev`
- #2 [stale-value] README.md:564 — threat IP synced to gatus.yaml
…

## Test scenarios
| # | Scenario | Result |
|---|---|---|
| 1 | Internet → AppGW | PASS |
| 2 | East-west cross-cluster | PASS |
| 3 | DCF egress allowed | PASS |
…

## Resources verified clean
- 0 orphan resource groups in <subscription>
- 0 stale state entries
```

The skill writes this file before opening the PR; `gh pr create --body @<report-path>` consumes it directly.

## Lifecycle Phases

The skill walks the README from top to bottom, treating each section as ground truth. Phases run in order:

### Phase 0 — Bootstrap (no cloud touched)

1. **Determine blueprint path.** First arg is `<blueprint-name>`. Resolve to `blueprints/<arg>/`. If that directory doesn't exist, abort with: `Blueprint not found: blueprints/<arg>/`.
2. **Branch handling.**
   - Run `git rev-parse --abbrev-ref HEAD`.
   - If on `main` (or whatever `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` returns), construct branch name `qa/<blueprint-name>-$(date +%Y-%m-%d)-<n>` where `<n>` is the lowest unused integer (check both local `git branch --list` and remote `git ls-remote --heads origin`). Run `git checkout -b <branch>`.
   - Otherwise, stay on the current branch (lets the user stack QA on top of a feature branch).
3. **Source Aviatrix env.** Resolve `${AVIATRIX_ENV_FILE:-$HOME/Documents/Scripting/chris-avx-lab/controller_env_ga.sh}`. Verify file exists (`test -f`). Source it. Verify `AVIATRIX_CONTROLLER_IP`, `AVIATRIX_USERNAME`, `AVIATRIX_PASSWORD` are now set.
4. **Detect target cloud(s).** `grep -lE "provider \"(azurerm|aws|google)\"" blueprints/<name>/**/*.tf` — collect the union of provider blocks across all `.tf` files in the blueprint.
5. **Verify cloud auth** for each detected cloud:
   - Azure: `az account show --query id -o tsv` — non-empty
   - AWS: `aws sts get-caller-identity --query Account --output text` — non-empty
   - GCP: `gcloud auth list --filter=status:ACTIVE --format="value(account)"` — non-empty
6. **Verify `gh` auth.** `gh auth status` exits 0.
7. **Create run state dir.** `RUN_DIR=/tmp/qa-blueprint-<name>-$(date +%Y%m%d-%H%M%S); mkdir -p "$RUN_DIR"; touch "$RUN_DIR/gaps.md"`.

If any step in Phase 0 fails, abort with a specific remediation message. **No cloud resources have been touched yet, so no destroy is required.**

### Phase 1 — Parse README + dry-run

1. Read `blueprints/<name>/README.md`.
2. Identify these sections (by `## ` headers):
   - Prerequisites
   - Deployment Guide (or "Complete Deployment Guide", "Deploy", or similar)
   - Test Scenarios
   - Destroy Instructions (or "Destroy", "Cleanup", "Teardown")
3. Within the Deployment Guide section, identify each `### Step N:` as a phase to execute. Note which steps are described as "parallel with step N+1" or "in parallel" — those are parallelism opportunities.
4. Within Test Scenarios, identify each `### Scenario N:` as a test to run.
5. Within Destroy Instructions, identify each `### Step N:` as a destroy phase to execute in order. Note any `> [!IMPORTANT]` callouts inside destroy steps — those usually flag known eventual-consistency issues with documented recovery.
6. Build the phase plan as a markdown summary in `$RUN_DIR/phase-plan.md`.
7. **If `--dry-run` was passed**, print `phase-plan.md` to stdout and exit 0. Do not proceed to Phase 2.

### Phase 2 — Pre-flight

1. **Run any pre-flight scripts the README contains.** Heuristic: search the Prerequisites section for fenced bash blocks that contain comments like `# Fail-fast pre-flight check` or are described as "preflight" / "verify quotas" / similar. Run them as-is. Capture exit code and output to `$RUN_DIR/phase-2-preflight.log`. **Non-zero exit → log a gap (category: `wrong-expected-output` or `unstated-prereq`) but do not abort.** A customer hitting the same wall would simply note it and try the deploy anyway.
2. **`terraform fmt -check -recursive blueprints/<name>/`.** If non-zero, log a gap (category: `readme-code-mismatch` if there's documented "always run fmt" guidance, otherwise just note as `phase-2 fmt drift`). Do not abort.
3. **`terraform validate` per layer.** For each `.tf`-containing leaf directory under `blueprints/<name>/`, run `terraform init -backend=false && terraform validate`. Failures here are gaps; do not abort.

### Phase 3 — Deploy

For each step in the parsed Deployment Guide:

1. **Read the step's prose + code blocks.** Identify the working directory (`cd ...`), the variables to set in `terraform.tfvars`, and the apply command.
2. **Variable filling.** For each variable the README requires:
   1. **Project memory first** — known values from memory file (e.g., `aviatrix_azure_account_name = "Azure"`).
   2. **Example file's documented default next** — if `terraform.tfvars.example` says `name_prefix = "aks-demo"`, use that.
   3. **Sensible inference last** — `azure_region` matches Tested With table, IP ranges from CIDR Allocation table, etc.
   4. If none of those work → log gap "README requires `<var>` without a documented value", set placeholder `qa-test-<random>`.
3. **Run terraform init + apply.** Use background invocation + Monitor for long-running applies (>5 min). Log full stdout/stderr to `$RUN_DIR/phase-3-deploy.log`.
4. **Parallelism.** When the README marks two steps as "parallel with…" (e.g., "Steps 5 and 6 can run in parallel in separate terminals"), launch both terraform applies in the background concurrently. Wait for both to complete before moving to the next non-parallel step.
5. **Transient retries.** If an apply fails with one of the known transient signatures below, retry once with the same args:
   - `connection reset by peer`
   - `502 Bad Gateway`
   - `i/o timeout`
   - `ResourceGroupBeingDeleted`
   - `listClusterUserCredential.*404`

   Successful retry → informational note in report (only a gap if the README didn't already document the transient). Second failure → log gap "deploy step <N> failed: <error>", **abort Phase 3, jump to Phase 5 (destroy)**.
6. **Per-step verification.** Some steps include `# Verify` sub-blocks. Run these and log their pass/fail. Failures are gaps.
