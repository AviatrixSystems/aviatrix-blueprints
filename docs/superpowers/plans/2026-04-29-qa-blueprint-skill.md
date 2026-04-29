# `/qa-blueprint` Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single procedural Claude Code slash-command skill (`/qa-blueprint`) that AI-QAs an Aviatrix blueprint by deploying it as a customer who only reads the README, captures UX gaps, applies fixes, and opens a PR.

**Architecture:** A single SKILL.md file at `.claude/skills/qa-blueprint/SKILL.md` containing YAML frontmatter and prose-driven instructions for the agent. Replaces the existing `.claude/skills/test-blueprint/SKILL.md`. No code, no helper scripts — the SKILL.md *is* the implementation. The tests of correctness are: (1) frontmatter parses, (2) skill is discoverable by Claude Code, (3) a `--dry-run` invocation against an existing blueprint produces a sensible phase plan without deploying.

**Tech Stack:** Markdown + YAML frontmatter, Bash, Python (for in-skill YAML parsing), `gh` CLI, `terraform`, `git`. Spec lives at `docs/superpowers/specs/2026-04-29-qa-blueprint-design.md`.

---

## File Structure

**Files this plan creates:**
- `.claude/skills/qa-blueprint/SKILL.md` — the new skill (single file, ~600 lines of markdown)

**Files this plan deletes:**
- `.claude/skills/test-blueprint/SKILL.md` — replaced by qa-blueprint
- `.claude/skills/test-blueprint/` — directory removed

**Files this plan does NOT touch:**
- `.claude/skills/{analyze,deploy,validate}-blueprint/` — left alone
- Any blueprint files
- The spec at `docs/superpowers/specs/2026-04-29-qa-blueprint-design.md`

---

## Task 1: Remove old test-blueprint skill

**Files:**
- Delete: `.claude/skills/test-blueprint/`

The new skill replaces test-blueprint per the spec. Deleting it first prevents two skills with overlapping intent.

- [ ] **Step 1: Verify no other code references test-blueprint**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints
grep -rn "test-blueprint" --exclude-dir=.git --exclude-dir=node_modules . 2>/dev/null
```

Expected: only matches inside `.claude/skills/test-blueprint/` and possibly `CLAUDE.md` / root README mentions. List any external references — if a CLAUDE.md or root README references `/test-blueprint`, plan an inline edit in this task to swap it for `/qa-blueprint`. If none, proceed.

- [ ] **Step 2: Update CLAUDE.md and root README references (if any)**

If Step 1 found references, edit them to say `/qa-blueprint` instead of `/test-blueprint`. Use the Edit tool. Skip this step if no external references were found.

- [ ] **Step 3: Delete the test-blueprint directory**

```bash
rm -rf /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.claude/skills/test-blueprint
ls /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.claude/skills/
```

Expected: directory listing shows only `analyze-blueprint`, `deploy-blueprint`, `validate-blueprint` (no `test-blueprint`).

- [ ] **Step 4: Commit the removal**

```bash
git add -A .claude/ CLAUDE.md  # CLAUDE.md only if you edited it in step 2
git commit -m "$(cat <<'EOF'
qa-blueprint: remove test-blueprint in favor of qa-blueprint

test-blueprint verifies "does it work?"; qa-blueprint (incoming)
verifies "does it work for a customer reading only the README?"
The two have different audiences and different success criteria,
so qa-blueprint replaces rather than runs alongside test-blueprint.

See docs/superpowers/specs/2026-04-29-qa-blueprint-design.md.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected: commit succeeds.

---

## Task 2: Create skill directory and write the frontmatter

**Files:**
- Create: `.claude/skills/qa-blueprint/SKILL.md`

The frontmatter is what Claude Code parses to discover the skill, set tool permissions, and bind argument hints. Getting this right matters more than the prose — wrong frontmatter means the skill is unusable regardless of how good the body is.

- [ ] **Step 1: Create the skill directory**

```bash
mkdir -p /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.claude/skills/qa-blueprint
```

Expected: directory exists.

- [ ] **Step 2: Write SKILL.md with frontmatter only (everything else added in later tasks)**

Use the Write tool to create `.claude/skills/qa-blueprint/SKILL.md` with these exact contents:

```markdown
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

(body added in subsequent tasks)
```

- [ ] **Step 3: Verify the frontmatter parses as valid YAML**

```bash
python3 -c "
import yaml, sys
with open('/Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.claude/skills/qa-blueprint/SKILL.md') as f:
    content = f.read()
parts = content.split('---', 2)
if len(parts) < 3:
    print('FAIL: not enough --- delimiters'); sys.exit(1)
front = yaml.safe_load(parts[1])
required = {'name', 'description', 'argument-hint', 'allowed-tools'}
missing = required - set(front.keys())
if missing:
    print(f'FAIL: missing keys: {missing}'); sys.exit(1)
print(f'OK: name={front[\"name\"]}, allowed-tools={len(front[\"allowed-tools\"])} entries')
"
```

Expected: `OK: name=qa-blueprint, allowed-tools=21 entries`

- [ ] **Step 4: Commit the scaffold**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints
git add .claude/skills/qa-blueprint/SKILL.md
git commit -m "qa-blueprint: scaffold SKILL.md with frontmatter

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Expected: commit succeeds.

---

## Task 3: Write top-level user-facing sections (Purpose, Usage, Prerequisites)

**Files:**
- Modify: `.claude/skills/qa-blueprint/SKILL.md`

These sections explain the skill to humans — agent behavior is defined later. Keep prose tight; the spec is the source of truth, this is a friendly summary.

- [ ] **Step 1: Replace the placeholder body with intro sections**

Use Edit to replace the line `(body added in subsequent tasks)` in `.claude/skills/qa-blueprint/SKILL.md` with the following content:

````markdown
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
````

- [ ] **Step 2: Verify the file has the new sections**

```bash
grep -n "^## " /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.claude/skills/qa-blueprint/SKILL.md
```

Expected output:
```
N: ## Usage
N: ## Prerequisites
N: ## What this skill does NOT do
```

(Where N = some line number — confirm three `## ` headers appear in this order.)

- [ ] **Step 3: Commit**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints
git add .claude/skills/qa-blueprint/SKILL.md
git commit -m "qa-blueprint: add user-facing intro, usage, prerequisites

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Expected: commit succeeds.

---

## Task 4: Write the Customer-Mindset Rules section

**Files:**
- Modify: `.claude/skills/qa-blueprint/SKILL.md`

This is the heart of the skill. The rules here govern agent behavior in every later phase. If this section is fuzzy, the agent will silently use insider knowledge and miss gaps.

- [ ] **Step 1: Append the Customer-Mindset Rules section**

Use Edit to append the following after the `## What this skill does NOT do` section:

````markdown

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
````

- [ ] **Step 2: Verify section is present**

```bash
grep -c "^## Customer-Mindset Rules" /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.claude/skills/qa-blueprint/SKILL.md
```

Expected: `1`

- [ ] **Step 3: Commit**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints
git add .claude/skills/qa-blueprint/SKILL.md
git commit -m "qa-blueprint: define customer-mindset rules + gap categories

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Expected: commit succeeds.

---

## Task 5: Write the Gap-Tracking Format section

**Files:**
- Modify: `.claude/skills/qa-blueprint/SKILL.md`

The format defines how Phase 6 (gap consolidation) finds and applies fixes. Loose format → the agent generates inconsistent gap entries → fix phase produces brittle edits.

- [ ] **Step 1: Append the Gap-Tracking Format section**

Use Edit to append the following after the `What is NOT a gap` block (after Task 4's content):

`````markdown

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
`````

- [ ] **Step 2: Verify section + nested code fences are intact**

```bash
grep -nE "^## Gap-Tracking|^### " /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.claude/skills/qa-blueprint/SKILL.md
```

Expected output includes:
```
## Gap-Tracking Format
### Run state directory
### gaps.md schema
### report.md format
```

- [ ] **Step 3: Commit**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints
git add .claude/skills/qa-blueprint/SKILL.md
git commit -m "qa-blueprint: define gap-tracking format and report schema

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Expected: commit succeeds.

---

## Task 6: Write Phases 0–3 (Bootstrap, Parse, Pre-flight, Deploy)

**Files:**
- Modify: `.claude/skills/qa-blueprint/SKILL.md`

These are the agent's runbook for the early phases. Per the spec, these phases must always run in order; later phases depend on the artifacts these produce (run state dir, parsed phase plan, deployed resources).

- [ ] **Step 1: Append the Lifecycle / Phases 0-3 sections**

Use Edit to append the following after the report.md format section:

````markdown

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
````

- [ ] **Step 2: Verify the new sections exist**

```bash
grep -nE "^### Phase [0-9]" /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.claude/skills/qa-blueprint/SKILL.md
```

Expected output includes:
```
### Phase 0 — Bootstrap (no cloud touched)
### Phase 1 — Parse README + dry-run
### Phase 2 — Pre-flight
### Phase 3 — Deploy
```

- [ ] **Step 3: Commit**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints
git add .claude/skills/qa-blueprint/SKILL.md
git commit -m "qa-blueprint: phases 0-3 (bootstrap, parse, preflight, deploy)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Expected: commit succeeds.

---

## Task 7: Write Phases 4–5 (Test, Destroy)

**Files:**
- Modify: `.claude/skills/qa-blueprint/SKILL.md`

Phase 5 is the most safety-critical phase — it must always run after Phase 3 starts, regardless of Phase 3's outcome.

- [ ] **Step 1: Append Phase 4 + Phase 5 sections**

Use Edit to append the following after Phase 3's content:

````markdown

### Phase 4 — Run test scenarios

For each scenario identified in Phase 1's parse:

1. **Read the scenario's code blocks and prose.** Some scenarios are pure CLI checks (curl, kubectl); some require manual UI inspection (e.g., CoPilot SmartGroup Members). For UI-only scenarios, mark as `MANUAL` in the scenario table — do not log a gap unless the README claims the API/CLI exposes the same data.
2. **Execute each command in the scenario's code block in order.** Capture exit codes, stdout, stderr.
3. **Verify expected output.** The README often includes `# Expected: 200` or similar comments. Match the actual output against expected. Mismatch → gap (category: `wrong-expected-output`), but **continue** — failed scenarios are documentation, not deploy aborts.
4. **For Gatus-based scenarios**, query Gatus's `/api/v1/endpoints/statuses` JSON endpoint via the public AppGW IP rather than relying on visual dashboard inspection. Parse the JSON; for each endpoint, check `success` matches the documented expectation (Egress = true, Threats = false).
5. **Log per-scenario result** to `$RUN_DIR/phase-4-test.log` and the running scenario table in `report.md`.

### Phase 5 — Destroy (always runs after Phase 3 starts)

Walk the README's Destroy Instructions in order (the README's destroy section is already in reverse-deploy order).

1. **Per-step transient-retry policy is the same as Phase 3.** Once retried failures are still failures.
2. **Documented recovery procedures are first-class steps.** When the README says `> [!IMPORTANT] If you hit X, do Y…`, treat that as a *known* recovery path. If step X fails with the matching signature, run the documented recovery Y, then re-run step X. If recovery succeeds, log informational note "documented recovery used"; if recovery fails, log a gap (category: `missing-recovery`) and continue best-effort.
3. **Always-run guarantee.** Even if Phase 3 aborted partway, attempt every destroy step that targets a layer Terraform created. Use `terraform state list` to determine which layers have non-empty state.
4. **Orphan check at end.**
   - Cloud-side: query for resources tagged or named with the blueprint's `name_prefix`. Examples:
     - Azure: `az group list --query "[?contains(name, '<name_prefix>')].name" -o tsv`
     - AWS: `aws ec2 describe-vpcs --filters "Name=tag:Blueprint,Values=<name>" --query "Vpcs[].VpcId" --output text`
   - Terraform-side: every leaf dir's `terraform state list | wc -l` should return 0.
5. **Report.** Add a "Resources verified clean" line per cloud + the state-list summary to `report.md`.

If destroy fails entirely (orphan resources remain), do not abort the run — proceed to Phase 6 with the gap logged. The PR will document the orphans and include manual cleanup commands in the body.
````

- [ ] **Step 2: Verify the sections exist**

```bash
grep -nE "^### Phase [4-5]" /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.claude/skills/qa-blueprint/SKILL.md
```

Expected: includes `### Phase 4 — Run test scenarios` and `### Phase 5 — Destroy (always runs after Phase 3 starts)`.

- [ ] **Step 3: Commit**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints
git add .claude/skills/qa-blueprint/SKILL.md
git commit -m "qa-blueprint: phases 4-5 (test scenarios, destroy)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Expected: commit succeeds.

---

## Task 8: Write Phases 6–8 (Fix, Commit/PR, Cleanup)

**Files:**
- Modify: `.claude/skills/qa-blueprint/SKILL.md`

Phase 6 is the trickiest — it has to consolidate gaps that may overlap, generate non-conflicting edits, and bail out cleanly on fmt-check failure without leaving the repo in a broken state.

- [ ] **Step 1: Append Phases 6–8**

Use Edit to append after Phase 5's content:

````markdown

### Phase 6 — Gap consolidation + fix

1. **Read** `$RUN_DIR/gaps.md`.
2. **Group gaps by `file:`** — every gap targets one or more files via `files_to_edit`. Build a per-file list.
3. **For each file**, generate a single consolidated set of Edits:
   1. Re-read the file fully (so line numbers are current — earlier fixes in this run may have shifted them).
   2. For each gap touching this file, derive the exact Edit (old_string / new_string) from `fix_proposal`. Use unique-anchor strings, not line numbers.
   3. Apply all edits to this file in one logical batch.
4. **Validate** with `terraform fmt -check -recursive blueprints/<name>/`. Non-zero exit → **revert the edits for the offending file** (`git checkout -- <file>`), log "fmt conflict for `<file>`: <output>" to `$RUN_DIR/phase-6-fix-plan.md`, **do not commit**.
5. **Write `$RUN_DIR/phase-6-fix-plan.md`** with one section per fixed file (gap IDs + diff summary). This is for the human reviewing the PR.

### Phase 7 — Commit + PR

1. **Generate `$RUN_DIR/report.md`** per the schema in the Gap-Tracking Format section.
2. **Stage only files that gaps touched.** Do not `git add -A` (avoids staging unrelated working-tree changes).
3. **Commit** on the current branch:

   ```bash
   git commit -m "$(cat <<'EOF'
   <blueprint>: QA pass — <N> gap fix(es)

   <one-line summary per gap>
   - <gap #1 summary>
   - <gap #2 summary>

   Run report: $RUN_DIR/report.md

   Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
   EOF
   )"
   ```

   No `--no-verify`. If a hook fails, surface the error and abort Phase 7 — fixes stay uncommitted, state dir kept.

4. **Push.** `git push -u origin <branch>`. If the upstream is already set, just `git push`.
5. **Open PR.**

   ```bash
   default_branch=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
   gh pr create \
     --base "$default_branch" \
     --title "<blueprint>: QA pass YYYY-MM-DD" \
     --body-file "$RUN_DIR/report.md"
   ```

   No labels, milestones, assignees, or auto-merge in v1.

6. **Print PR URL** to stdout.

### Phase 8 — Cleanup

- **Full success** (every prior phase exit-clean, fixes pushed, PR opened) → `rm -rf "$RUN_DIR"` and print one-line summary.
- **Partial failure** anywhere from Phase 3 onward → leave `$RUN_DIR` in place, print its path so the user can resume / investigate.
````

- [ ] **Step 2: Verify**

```bash
grep -nE "^### Phase [6-8]" /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.claude/skills/qa-blueprint/SKILL.md
```

Expected: three matches — Phase 6, 7, 8.

- [ ] **Step 3: Commit**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints
git add .claude/skills/qa-blueprint/SKILL.md
git commit -m "qa-blueprint: phases 6-8 (fix, commit/PR, cleanup)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Expected: commit succeeds.

---

## Task 9: Write Failure Handling section

**Files:**
- Modify: `.claude/skills/qa-blueprint/SKILL.md`

Per-phase failure behavior is partially documented inside each phase (Tasks 6–8). This section consolidates the cross-phase rules and the self-failure path so the agent has one place to look.

- [ ] **Step 1: Append the Failure Handling section**

Use Edit to append after Phase 8:

````markdown

## Failure Handling (cross-phase rules)

### Transient retry policy

Retry-once errors:

- `connection reset by peer`
- `502 Bad Gateway`
- `i/o timeout`
- `ResourceGroupBeingDeleted`
- `listClusterUserCredential.*404`

Retry behavior is identical for `terraform apply` (Phase 3) and `terraform destroy` (Phase 5). One retry, same args, no escalation. Succeeded retry → informational note in `report.md` (only logged as a gap if the README didn't already mention the transient).

### Per-phase fatal-failure summary

| Phase | On fatal failure |
|---|---|
| 0 — bootstrap | Abort. No cloud touched. Print remediation. State dir not created. |
| 1 — parse | Abort. Likely malformed README. Print parse failure. |
| 2 — pre-flight | Continue. Pre-flight failures are gaps, not aborts. |
| 3 — deploy | Skip Phase 4. **Always run Phase 5.** Log gap "deploy failed at <step>". |
| 4 — test | Continue. Failed scenarios are gaps. |
| 5 — destroy | Best-effort. Orphan resources reported with explicit cleanup commands. State dir kept. |
| 6 — fix | If fmt-check fails after edits, revert edits for affected files, log conflict, do not commit. State dir kept. |
| 7 — commit/PR | If push or `gh` fails, fixes stay on the local branch with the commit; user pushes manually. |

### Always-run guarantees

- **Phase 5 always runs after Phase 3 starts.** If the agent crashes mid-deploy, the next invocation of `/qa-blueprint <name>` detects an existing `/tmp/qa-blueprint-<name>-*` dir and prompts the user before starting fresh.
- **State dir never deleted on failure.** Cleanup happens only on full success.

### Self-failure path

If the agent itself errors out (LSP died, an unexpected tool error), print:

```
QA run aborted. State preserved at /tmp/qa-blueprint-<name>-<ts>/

Resources may still be deployed. Verify with:
  <cloud-specific check derived from the parsed README>
  e.g. Azure: az group list --query "[?contains(name, '<name_prefix>')].name" -o tsv

To clean up, re-run /qa-blueprint <name> or destroy manually:
  <cloud-specific destroy command derived from the parsed README's destroy section>
```

The remediation hints come from the parsed Phase 1 plan, not hardcoded.
````

- [ ] **Step 2: Verify**

```bash
grep -nE "^## Failure Handling|^### " /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.claude/skills/qa-blueprint/SKILL.md | tail -10
```

Expected: includes `## Failure Handling (cross-phase rules)`, `### Transient retry policy`, `### Per-phase fatal-failure summary`, `### Always-run guarantees`, `### Self-failure path`.

- [ ] **Step 3: Commit**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints
git add .claude/skills/qa-blueprint/SKILL.md
git commit -m "qa-blueprint: cross-phase failure handling and recovery

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Expected: commit succeeds.

---

## Task 10: Write Implementation Notes + Open Questions

**Files:**
- Modify: `.claude/skills/qa-blueprint/SKILL.md`

Closing sections that capture mechanical gotchas (so future debugging finds them quickly) and explicit non-features (so future PRs don't waste time scope-creeping).

- [ ] **Step 1: Append the closing sections**

Use Edit to append after Failure Handling:

````markdown

## Implementation Notes

- **`source` is a shell builtin, not a binary.** Each Bash tool call spawns a fresh shell, so chain `source <file>` with the actual command via `&&`. Example:
  ```bash
  source "$AVIATRIX_ENV_FILE" && terraform apply -auto-approve
  ```
  If `Bash(source *)` doesn't get permission-allowed at runtime, fall back to inlining: `set -a; . "$AVIATRIX_ENV_FILE"; set +a`.

- **Default-branch detection.**
  ```bash
  default_branch=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
  ```
  Use this rather than hardcoding `main`.

- **Resume detection** (Phase 5 always-run guarantee). On entry, after parsing args:
  ```bash
  existing=$(ls -1d "/tmp/qa-blueprint-<name>"-* 2>/dev/null | head -1)
  ```
  If `$existing` is non-empty, prompt the user: "Existing run dir found at `$existing`. Resume from destroy, or start fresh? (resume/fresh)". Only continue once the user picks.

- **Long-running waits.** Phase 3 applies (network, AKS clusters) take 5–15 min. Use `Bash(... &)` + the Monitor tool with a tight regex (`Apply complete|Error:|^Error |502 Bad Gateway`) to avoid context bloat from `Still creating…` lines.

- **Multi-layer parallelism.** When the README marks two layers as "parallel with…", launch both in the background and use a single Monitor watching `tail -F file1 file2`. Both must complete before moving on.

- **Tool permissions.** `allowed-tools` covers binary invocations and the major Claude tools. If the runtime rejects an unlisted invocation, document the missing entry as a follow-up (do not bypass with shell tricks).

## Open questions / future work

These are intentionally out of scope for v1. PRs welcome.

- **Multi-cloud blueprints** (e.g., `k8s-cluster-aas/aws`, `…/azure`, `…/gcp`): v1 handles one cloud per invocation. The arg `<blueprint-name>` accepts the cloud subpath (e.g., `k8s-cluster-aas/aws`). Future: orchestrate all three in one run.
- **Playwright/CoPilot UI verification.** v1 is text-only. The original `test-blueprint` had Playwright integration; if we need it back, it goes into a separate `--with-ui` mode.
- **Iteration mode.** v1 is one-pass. If a user wants "deploy → fix → redeploy until two passes find no new gaps", add `--loop` later.
- **Cost ceiling.** v1 has no spend cap. A future `--max-cost-usd <N>` could abort if estimated spend exceeds the cap.
````

- [ ] **Step 2: Verify**

```bash
grep -nE "^## " /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.claude/skills/qa-blueprint/SKILL.md
```

Expected: prints `## ` headers in this order: Usage, Prerequisites, What this skill does NOT do, Customer-Mindset Rules, Gap-Tracking Format, Lifecycle Phases, Failure Handling, Implementation Notes, Open questions / future work.

- [ ] **Step 3: Commit**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints
git add .claude/skills/qa-blueprint/SKILL.md
git commit -m "qa-blueprint: implementation notes and open questions

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Expected: commit succeeds.

---

## Task 11: Validate the SKILL.md (frontmatter, structure, no contradictions)

**Files:**
- Read-only check on `.claude/skills/qa-blueprint/SKILL.md`

A self-review pass against the spec before smoke testing.

- [ ] **Step 1: Re-validate the YAML frontmatter**

```bash
python3 -c "
import yaml, sys
with open('/Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.claude/skills/qa-blueprint/SKILL.md') as f:
    parts = f.read().split('---', 2)
front = yaml.safe_load(parts[1])
assert front['name'] == 'qa-blueprint'
assert 'AI-QA' in front['description']
assert front['argument-hint'] == '<blueprint-name> [--dry-run]'
assert front['disable-model-invocation'] is True
assert any('terraform' in t for t in front['allowed-tools'])
assert any('gh' in t for t in front['allowed-tools'])
assert 'Read' in front['allowed-tools']
assert 'Write' in front['allowed-tools']
assert 'Edit' in front['allowed-tools']
print('frontmatter OK')
"
```

Expected: `frontmatter OK`

- [ ] **Step 2: Confirm all required sections are present**

```bash
SKILL=/Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.claude/skills/qa-blueprint/SKILL.md
for section in "## Usage" "## Prerequisites" "## Customer-Mindset Rules" "## Gap-Tracking Format" "## Lifecycle Phases" "### Phase 0" "### Phase 1" "### Phase 2" "### Phase 3" "### Phase 4" "### Phase 5" "### Phase 6" "### Phase 7" "### Phase 8" "## Failure Handling" "## Implementation Notes" "## Open questions"; do
  if grep -qF "$section" "$SKILL"; then
    echo "OK   $section"
  else
    echo "MISSING $section"
  fi
done
```

Expected: every line begins with `OK`. If any `MISSING`, go back to the relevant Task and add the missing section.

- [ ] **Step 3: Cross-check spec coverage**

Open `docs/superpowers/specs/2026-04-29-qa-blueprint-design.md` and read each `## ` and `### ` heading. For each spec section, confirm the SKILL.md has equivalent content.

Spec → SKILL.md mapping:

| Spec section | SKILL.md section |
|---|---|
| Purpose | (top of file, prose intro) |
| Architecture | Implementation Notes |
| State during a run | Gap-Tracking Format → Run state directory |
| Lifecycle phases (each) | Lifecycle Phases → Phase 0–8 |
| Customer-mindset rules | Customer-Mindset Rules |
| Gap categories | Customer-Mindset Rules → Gap categories |
| Gap-tracking format | Gap-Tracking Format → gaps.md schema |
| Final report format | Gap-Tracking Format → report.md format |
| Branch + PR conventions | Phase 0 (branch) + Phase 7 (commit/PR) |
| Failure handling | Failure Handling |
| Implementation notes | Implementation Notes |
| Open questions / future work | Open questions / future work |

If anything spec-side has no SKILL.md mapping, add it now and re-commit.

- [ ] **Step 4: Spot-check internal consistency**

```bash
# Run dir name format must match across mentions
grep -n "/tmp/qa-blueprint-" /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints/.claude/skills/qa-blueprint/SKILL.md
```

Expected: every reference uses `/tmp/qa-blueprint-<name>-<timestamp>/` or `/tmp/qa-blueprint-<name>-*`. If you see two formats, normalize.

- [ ] **Step 5: No commit needed unless Step 3 surfaced a gap**

If you added missing content in Step 3, commit it:

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints
git add .claude/skills/qa-blueprint/SKILL.md
git commit -m "qa-blueprint: fill in spec-coverage gaps from validation

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Otherwise no commit; proceed to Task 12.

---

## Task 12: Smoke test the skill with `--dry-run` on `azure-aks-multicluster`

**Files:**
- Read-only — runs the skill against an existing blueprint without deploying

The first real test of whether the agent will follow the skill correctly. `--dry-run` exits before Phase 2 so no cloud resources get touched.

- [ ] **Step 1: Restart Claude Code so the new skill is discovered**

The user should `exit` and re-launch `claude` in the repo. Newly-created skills aren't always picked up mid-session.

After restart, in the new session, type `/qa-blueprint` and confirm autocomplete suggests it. If not, check `.claude/skills/qa-blueprint/SKILL.md` exists at the expected path.

- [ ] **Step 2: Invoke `--dry-run`**

In the new session, run:

```
/qa-blueprint azure-aks-multicluster --dry-run
```

The agent should:
1. Bootstrap (verify branch, env file, az login, gh auth).
2. Parse the README.
3. Print a phase plan (a markdown summary of what would run).
4. Exit cleanly without running Phase 2 or anything later.

- [ ] **Step 3: Inspect the printed phase plan**

Verify the plan includes:
- A list of deploy steps mirroring the README's Step 1–Step 8 in `azure-aks-multicluster/README.md`
- Test scenarios 1–7
- Destroy steps in reverse order
- Note about parallelism for Steps 3+4 (clusters) and Steps 5+6 (nodes)

If anything is missing or wrong, the issue is in the SKILL.md — either Phase 1 parsing rules need tightening or specific content needs to be more explicit. Edit, commit (one focused commit per fix), and re-run the dry-run.

- [ ] **Step 4: Confirm no side effects**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints
git status --short
ls /tmp/qa-blueprint-azure-aks-multicluster-* 2>/dev/null  # may exist with phase-plan.md but nothing else
az group list --query "[?contains(name, 'aks-demo')].name" -o tsv  # should be empty
```

Expected: no new commits beyond what we made; if the run dir exists it contains only `phase-plan.md` (no deploy logs); no `aks-demo*` Azure resource groups exist.

- [ ] **Step 5: Clean up the dry-run artifact**

```bash
rm -rf /tmp/qa-blueprint-azure-aks-multicluster-*
```

No commit needed.

---

## Task 13: Open the PR

**Files:**
- None modified (just push + PR)

- [ ] **Step 1: Push the branch**

```bash
cd /Users/christophermchenry/Documents/Scripting/aviatrix-blueprints
git push -u origin feat/qa-blueprint-skill 2>&1 | tail -5
```

Expected: `branch 'feat/qa-blueprint-skill' set up to track 'origin/feat/qa-blueprint-skill'.`

- [ ] **Step 2: Open the PR**

```bash
gh pr create --title "qa-blueprint: AI-as-customer QA skill" --body "$(cat <<'EOF'
## Summary

Adds `/qa-blueprint`, a Claude Code slash-command skill that AI-QAs an Aviatrix blueprint by deploying it as a customer using only the README, capturing UX gaps, applying fixes, and opening a PR per QA pass.

This replaces `/test-blueprint`. The two skills had overlapping plumbing but different intent: `test-blueprint` answers "does it work?" using engineer mindset; `qa-blueprint` answers "does it work *for a customer reading only the README?*". Different audience, different success criteria, so the unified `qa-blueprint` is one focused skill instead of two skills with conflicting authority over the same workflow.

Spec: `docs/superpowers/specs/2026-04-29-qa-blueprint-design.md`
Plan: `docs/superpowers/plans/2026-04-29-qa-blueprint-skill.md`

### What it does
- 8 phases: Bootstrap → Parse → Pre-flight → Deploy → Test → Destroy → Fix → Commit/PR → Cleanup
- Strict customer mindset for Phases 1–5 (README is sole source of truth; insider knowledge is verification-only)
- Gap tracking in `/tmp/qa-blueprint-<name>-<timestamp>/gaps.md` as fenced YAML
- Always-run destroy after deploy starts
- Auto-fix + commit + PR on a feature branch (no auto-merge)
- One pass per invocation; `--dry-run` for plan-only mode

### Notable design decisions
- Single procedural SKILL.md, no helper scripts (matches `analyze-blueprint`/`validate-blueprint` shape)
- Replaces test-blueprint rather than coexisting
- v1 is text-only — Playwright UI checks deferred to a future `--with-ui` flag

## Test plan
- [x] Frontmatter parses as valid YAML
- [x] All 9 spec-mandated sections present in SKILL.md
- [x] `/qa-blueprint <name> --dry-run` prints a sensible phase plan
- [x] Dry-run does not touch any cloud resources
- [x] Dry-run does not modify the working tree
- [ ] First real `/qa-blueprint azure-aks-multicluster` run (without `--dry-run`) lands a follow-up PR with any gaps from this skill's first end-to-end pass

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL printed.

- [ ] **Step 3: Wait for CI to pass, then merge**

```bash
gh pr checks --watch
gh pr merge --squash --delete-branch
```

Expected: all checks green, PR merged.

---

## Self-Review

(Run by the plan author before handing off — these checks already happened during writing.)

**Spec coverage:** every section in `docs/superpowers/specs/2026-04-29-qa-blueprint-design.md` maps to a Task above. The mapping table in Task 11 Step 3 is the cross-reference.

**Placeholder scan:** no "TBD", "TODO", "implement later", "appropriate error handling", or "similar to Task N" — every task has full content the engineer can paste.

**Type/path consistency:** `/tmp/qa-blueprint-<name>-<timestamp>/` is used identically across all phase descriptions; `$AVIATRIX_ENV_FILE`, `$RUN_DIR` referenced consistently; `<blueprint-name>` and `<name>` are interchangeable in the spec, kept that way here.
