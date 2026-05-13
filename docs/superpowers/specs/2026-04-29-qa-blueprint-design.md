# `/qa-blueprint` skill — design

**Status:** approved 2026-04-29
**Replaces:** `.claude/skills/test-blueprint/`
**Branch:** `feat/qa-blueprint-skill`

## Purpose

Automate AI-as-customer QA of an Aviatrix blueprint. The skill deploys the blueprint by following only what the README literally says, runs every documented test scenario, destroys in reverse order, captures every UX gap that surfaces (copy-paste failures, stale values, README↔code mismatches, missing prereqs), applies fixes, and opens a PR. One pass per invocation.

This is different from `test-blueprint` (which verifies "does it work?" using engineer mindset). `/qa-blueprint` verifies "does it work *for a customer reading only the README?*" The two have different audiences and different success criteria, so `/qa-blueprint` replaces `test-blueprint` rather than running alongside it.

## Architecture

Single procedural skill: `.claude/skills/qa-blueprint/SKILL.md`. No helpers, no sub-directories. Matches the shape of the existing `analyze-blueprint` and `validate-blueprint` skills.

Frontmatter:

```yaml
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
  - Bash(source *)
  - Read
  - Edit
  - Write
  - Glob
  - Grep
---
```

`--dry-run` parses the README and prints the phase plan without deploying.

### State during a run

`/tmp/qa-blueprint-<name>-<timestamp>/`:

- `gaps.md` — running gap list (one fenced YAML block per gap)
- `phase-*.log` — per-phase output
- `gap-fix-plan.md` — consolidated edits before applying
- `report.md` — final run report (also used as PR body)

Auto-cleaned on full success; preserved on failure for inspection or resume.

## Lifecycle phases

The agent walks the README top-to-bottom, treating each section as ground truth.

### Phase 0 — Bootstrap

- Verify on a feature branch (auto-create `qa/<blueprint>-YYYY-MM-DD-<n>` if on main)
- Source `$AVIATRIX_ENV_FILE` (default `~/Documents/Scripting/chris-avx-lab/controller_env_ga.sh`, overridable)
- Detect cloud(s) by grepping the blueprint's `*.tf` for provider blocks (`azurerm`, `aws`, `google`)
- Verify each cloud's CLI is logged in (`az account show`, `aws sts get-caller-identity`, `gcloud auth list`)
- Failure → abort with a specific remediation message. **No cloud resources touched.**

### Phase 1 — README parse + dry-run

- Read the README. Identify: prerequisites, deployment steps, test scenarios, destroy steps
- Build an internal phase plan
- If `--dry-run`, print the plan and exit

### Phase 2 — Pre-flight

- Run any "fail-fast" pre-flight scripts the README contains (e.g., quota check)
- Run `terraform fmt -check -recursive` and `terraform validate` on each layer
- Failures here are gaps logged + the deploy still proceeds (a customer would hit the same wall)

### Phase 3 — Deploy

- Walk the README's deploy section
- For each layer: `cp tfvars.example tfvars`, fill the minimal documented variables in this priority order:
  1. **Project memory** — e.g., `aviatrix_azure_account_name = "Azure"` is in the user's memory file as the controller-side Azure account name; use it directly
  2. **Example file's documented default** — if the example file has `name_prefix = "aks-demo"` as the placeholder, keep it
  3. **Sensible inference** — `azure_region = "eastus2"` matches the `Tested With` table in the README
- Variables that are required-but-no-good-default → log a gap *"README requires `<var>` without a documented value"* and use `"qa-test-<random>"` placeholder
- Run `terraform init -upgrade` then `terraform apply`
- Multi-layer parallelism honored exactly as the README says
- Long-running applies run via background + Monitor

### Phase 4 — Test scenarios

- Execute every scenario in the README's "Test Scenarios" section, in order
- Capture pass/fail per scenario
- A failed scenario is a gap (deploy "completed" but documented behavior didn't match)

### Phase 5 — Destroy

- Walk the README's destroy section in reverse order
- Same gap-tracking applies — documented "if you hit X, do Y" recovery procedures that fail are also gaps
- **Always runs** after Phase 3 starts, even if Phase 3 partially failed

### Phase 6 — Gap consolidation + fix

- Read `gaps.md`
- Group gaps by file
- For each file: re-read, generate a single consolidated Edit, apply
- Run `terraform fmt -check -recursive` afterward
- If fmt fails: undo, log "fix conflicted with fmt", surface to user instead of committing

### Phase 7 — Commit + PR

- Commit on the feature branch with structured message (gap summary as bullets)
- Push
- Open a PR via `gh pr create` with `report.md` as the body
- **No auto-merge** — merging is a human decision

### Phase 8 — Cleanup

- Full success → delete `/tmp/qa-blueprint-<name>-<timestamp>/`
- Otherwise leave state for inspection / resume

## Customer-mindset rules

The prime directive that separates `/qa-blueprint` from `test-blueprint`.

**During Phases 1–5, the README is the only source of truth for what to do.** Memory, prior conversation context, project lore — off-limits for *decisions*. They remain available for *verification* (checking whether the README's claims hold).

### Concrete rules

- **README silent → log gap, pick simplest interpretation, continue.** Don't fail the run on ambiguity; document it.
- **README says X, code says Y → log gap, follow README first.** The README is what a customer reads; code is what insiders read.
- **Documented command fails → log verbatim, retry once if transient, then pragmatic workaround or abort phase.** The workaround proves the gap fix.
- **Insider knowledge is for verification only.** `terraform state list`, controller API, etc. — fine for *checking* an outcome. Not for deciding the next step.
- **Memory cross-checks are diagnostic, not corrective.** "Memory says step X always fails" — agent still runs step X, observes the failure, logs the gap.

### Gap categories

| Category | Example |
|---|---|
| copy-paste-failure | Missing `kubectl create namespace`, `${ENV_VAR}` in tfvars |
| stale-value | Threat IP rotated, version bump needed |
| readme-code-mismatch | tf output missing `--context`, wrong subnet name |
| unstated-prereq | Step Y depends on X but X is in a separate section |
| wrong-expected-output | "Health: Healthy" claimed when probe still failing |
| missing-recovery | Documented step fails reliably; recovery exists but is in an easy-to-miss callout |
| ambiguous-wording | "your IP" vs "controller IP" vs "client IP" used inconsistently |

### Not gaps

- Personal style/formatting preferences
- Refactoring opportunities not customer-visible
- Issues already addressed by an open PR or recent commit (`git log --since="7 days ago"`)

## Gap-tracking format

Each gap is a fenced YAML block in `gaps.md`:

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
    webgrouppolicy-dev apply in the Scenario 6 code block.
  files_to_edit:
    - blueprints/azure-aks-multicluster/README.md
````

YAML in markdown: human-skimmable, machine-parseable in Phase 6, useful artifact even if the run aborts before the PR.

Gap IDs are stable within a run (1, 2, 3...) and referenced in the final PR body for traceability.

### Final report format

```markdown
# QA run: <blueprint-name>
- Branch: qa/<name>-2026-04-29-1
- Wall-clock: 28m
- Test scenarios: 6/7 pass (1 worked-around, see gap #3)

## Gaps found and fixed (5)
- #1 [copy-paste-failure] README.md:605 — missing `kubectl create namespace dev`
- #2 [stale-value] README.md:564 — threat IP synced to gatus.yaml
- ... (one bullet per gap, links to file:line)

## Test scenarios
| # | Scenario | Result |
|---|---|---|
| 1 | Internet → AppGW | ✅ |
| ... |

## Resources verified clean
- 0 orphan resource groups in <subscription>
- 0 stale state entries
```

## Branch + PR conventions

### Branch naming

When the user is on `main`:

```
qa/<blueprint-name>-YYYY-MM-DD-<n>
```

`<n>` is `1` for the first QA run on a given day, `2` if `qa/<blueprint>-YYYY-MM-DD-1` exists, etc. Local branches checked first, then remote.

When the user is already on a non-main branch, the skill uses that branch — lets the user stack a QA pass on top of in-progress work.

### Commit policy

All gap fixes go into a single commit at the end of the run:

```
<blueprint>: QA pass — <N> gap fix(es)

<one-line summary per gap>
- <gap #1 summary>
- <gap #2 summary>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

### PR creation

```
gh pr create --title "<blueprint>: QA pass YYYY-MM-DD" --body @<report-path>
```

PR is created against the repo's default branch (detected via `gh repo view --json defaultBranchRef`).

### Non-features (intentional)

- No PR labeling, milestoning, or assignment
- No multi-PR splitting (all fixes from one run land in one PR; user splits manually if needed)
- No auto-merge
- No `--no-verify`

## Failure handling

### Transient retries

Common transients per project memory:

- Aviatrix Controller `connection reset by peer` during `aviatrix_spoke_transit_attachment`
- Azure ARM `ResourceGroupBeingDeleted` during destroy
- AKS `listClusterUserCredential` 404 race

For these the skill **retries the same `terraform apply` / `terraform destroy` once**. Successful retry → informational note in the report (only a gap if README didn't already document the transient). Second failure → phase fatal.

### Phase fatal-failure behavior

| Phase | Failure → |
|---|---|
| 0 — bootstrap | Abort. No cloud touched. Report what's missing. |
| 1 — parse | Abort. Likely malformed README. Report the parse failure. |
| 2 — pre-flight | Continue. Pre-flight failures are themselves gaps. |
| 3 — deploy | Skip Phase 4. **Always run Phase 5.** Log gap "deploy failed at <step>". |
| 4 — test | Continue. Failed scenarios are gaps. |
| 5 — destroy | Best-effort. Orphan resources reported with explicit cleanup commands. State dir kept. |
| 6 — fix | If fmt-check fails, undo edits, surface to user, do not commit. State dir kept. |
| 7 — commit/PR | If push or gh fails, fixes stay on local branch with the commit; user can push manually. |

### Always-run guarantees

- **Phase 5 always runs after Phase 3 starts.** If the agent crashes, the next invocation detects existing state in `/tmp/qa-blueprint-<name>-*` and offers to resume from destroy.
- **State dir never deleted on failure.**

### Self-failure path

```
QA run aborted. State preserved at /tmp/qa-blueprint-<name>-<ts>/
Resources may still be deployed. Verify with:
  az group list --query "[?contains(name, '<name_prefix>')].name" -o tsv
To clean up, re-run /qa-blueprint <name> or destroy manually:
  cd <blueprint>/network && terraform destroy -auto-approve -var enable_k8s_smartgroup_demo=false
```

Remediation hints come from the parsed README's destroy section.

## Implementation notes

- **`source` is a shell builtin, not a binary.** The `Bash(source *)` allowed-tool entry covers users typing `source <file>` inside a Bash invocation. The actual mechanism is `bash -c "source <file>; <command>"`-style chaining since each Bash tool call spawns a fresh shell. Verify this works during implementation; fall back to inlining `set -a; . "$AVIATRIX_ENV_FILE"; set +a` if needed.
- **Default-branch detection:** `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`. Use this rather than hard-coding `main`.
- **Resume detection** (Phase 5 always-run guarantee): on entry, `ls -1 /tmp/qa-blueprint-<name>-* 2>/dev/null` — if any state dirs exist, prompt the user before deploying, asking whether to resume an aborted run or start fresh.

## Open questions / future work

- **Multi-cloud blueprints** (e.g., `k8s-cluster-aas/` with `aws/`, `azure/`, `gcp/` subdirs): the v1 skill handles only one cloud per invocation. User picks `aws` or `azure` etc. via the `<blueprint-name>` arg matching a subdirectory path. Future work: orchestrate all three in one run.
- **Playwright/CoPilot UI verification:** The original `test-blueprint` had Playwright integration for CoPilot UI checks. v1 of `/qa-blueprint` skips this (text-based verification only) and adds it later if needed.
- **Iteration mode:** v1 is one-pass. If a future need surfaces, add `--loop` flag that re-runs deploy → fix → redeploy until two passes find no new gaps.
