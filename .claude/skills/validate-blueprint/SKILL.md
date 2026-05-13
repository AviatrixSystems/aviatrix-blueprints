---
name: validate-blueprint
description: Pre-QA quality gate for Aviatrix blueprints. Runs tiered validation (blockers / standards / quality) and produces a QA-readiness verdict. Use before submitting a blueprint to QA, before merging, or whenever asked to "validate", "check", or "grade" a blueprint.
argument-hint: [blueprint-path]
allowed-tools:
  - Bash(terraform *)
  - Bash(ls *)
  - Bash(test *)
  - Bash(find *)
  - Bash(stat *)
  - Bash(git check-ignore *)
  - Bash(rm -rf *.terraform*)
  - Read
  - Grep
  - Glob
---

# Validate Blueprint (Pre-QA Gate)

Comprehensive pre-QA quality gate for Aviatrix blueprints. Verifies a blueprint will actually deploy and meets repository standards before it reaches QA.

## Usage

```
/validate-blueprint [blueprint-path]
```

If no path is provided, validate the current blueprint directory or ask which to validate.

## Verdict model

Validation produces one of three verdicts:

- **🚫 BLOCKED** — at least one Tier 1 check failed. **Do NOT send to QA.** Blueprint will not deploy.
- **⚠️ NEEDS WORK** — all Tier 1 pass, but Tier 2 has failures. Will deploy but violates repo standards.
- **✅ READY FOR QA** — Tier 1 + Tier 2 pass. Tier 3 warnings are advisory.

State the verdict prominently at the top AND bottom of the report.

## How to run

The blueprint may be:
- **Single-layer** (e.g. `azure-centralized-ingress/`): one directory with `main.tf`, `variables.tf`, etc.
- **Multi-layer** (e.g. `aws-eks-multicluster/`): subdirectories like `network/`, `clusters/<x>/`, `nodes/<x>/`, `k8s-apps/<x>/`.
- **Multi-cloud** (e.g. `k8s-cluster-aas/`): top-level `aws/`, `azure/`, `gcp/` directories, each potentially multi-layer underneath.

**First step in every run**: detect the shape. Use `Glob` and `ls` to find subdirectories. Then enumerate every Terraform "leaf" — a directory containing `*.tf` files where `terraform init` would actually be run. Apply per-leaf checks to each one. Apply per-cloud checks to each top-level cloud directory. Apply per-blueprint checks once at the root.

A good detection routine:

```bash
# Top-level cloud subdirs (multi-cloud test)
ls -d "$BP"/{aws,azure,gcp} 2>/dev/null

# Every Terraform leaf
find "$BP" -type f -name '*.tf' -not -path '*/.terraform/*' \
  -not -path '*/modules/*' \
  -exec dirname {} \; | sort -u
```

Treat any directory under `modules/` as a *module*, not a leaf — modules are validated structurally but `terraform init` is run only at leaves.

---

## Tier 1 — Deployment blockers (any failure = BLOCKED)

These are the checks that would have caught the broken k8s-* blueprints. Each is necessary; none is sufficient.

### T1.1 Every leaf passes `terraform init -backend=false`

This single check catches: missing module sources, broken external module paths, version constraint conflicts, missing required providers.

**Simulate a fresh checkout.** A pre-existing `.terraform/` directory or `.terraform.lock.hcl` left over from a previous local run can produce *false positives* (stale lock file referencing an old provider version) or *false negatives* (cached modules masking a now-broken source). Before running init, strip both. The repo gitignores `.terraform.lock.hcl` for blueprints, so deleting it never affects tracked files — but verify with `git check-ignore` if you're unsure.

For each leaf:
```bash
# Verify the lock file is gitignored before deleting (one-time check per repo is fine)
git check-ignore -q "$LEAF/.terraform.lock.hcl" || echo "WARN: lock file is tracked — preserve it"

# Fresh-checkout simulation
rm -rf "$LEAF/.terraform" "$LEAF/.terraform.lock.hcl"

( cd "$LEAF" && terraform init -backend=false -input=false -no-color ) 2>&1
```

Capture stdout+stderr. Any non-zero exit = fail. Report the offending leaf path and the first error line.

**Common failure pattern to flag explicitly**: `Error: Failed to download module` or `module not found` — usually means a `source = "../../../<sibling-blueprint>/modules/..."` reference points at something that doesn't exist.

**If the lock file is *tracked* in git** (the blueprint commits `.terraform.lock.hcl`), skip the `rm` of the lock file — that file is part of the contract and a stale lock IS a real T1.1 failure. Use `git check-ignore -q` to decide. The Aviatrix Blueprints repo currently gitignores all `.terraform.lock.hcl` files, but other repos may differ.

### T1.2 Every leaf passes `terraform validate`

After successful init:
```bash
( cd "$LEAF" && terraform validate -no-color ) 2>&1
```

### T1.3 All `module` source paths resolve

Grep every `*.tf` for `source = "..."` in a `module` block. For local sources (start with `./` or `../`), resolve the path relative to the file and verify the target directory exists and contains at least one `.tf` file.

```bash
# Find every module source
grep -rEn 'source\s*=\s*"\.\.?/' "$LEAF" --include='*.tf'
```

Flag any path that does not resolve. **Pay specific attention to `../../../../`-style paths that escape the blueprint** — these often reference sibling blueprints that may have moved or been renamed.

### T1.4 Every `terraform_remote_state` reference resolves to a real layer

Find all `data "terraform_remote_state"` blocks. For each, verify:
- `backend = "local"` (no remote backend leakage — `s3`, `azurerm`, `gcs`, `remote` are all forbidden)
- The `path` resolves to an existing layer directory (the `.tfstate` file itself need not exist yet — but the directory containing it must, and that directory must have `*.tf` files defining the outputs being referenced)

```bash
grep -rEn 'terraform_remote_state' "$LEAF" --include='*.tf' -A 5
```

### T1.5 Required variables are satisfiable

For each leaf's `variables.tf`, list every variable that has **no default and no value provided by an upstream `terraform_remote_state` output**. Cross-reference against:
- `terraform.tfvars.example` in the same directory, or
- A root-level `terraform.tfvars.example` for the cloud, or
- An `export AVIATRIX_*` style env var that the blueprint README documents.

If a leaf requires a manual `-var=cluster_endpoint=...` style input that the README doesn't document AND that isn't pulled from the cluster layer's outputs — that's a blocker. (This is exactly what kills `k8s-prod-nonprod-hybrid` Azure/GCP nodes.)

### T1.6 Multi-cloud parity for cloud subdirs

If `aws/`, `azure/`, or `gcp/` exists at the top level, the blueprint claims multi-cloud support. Each present cloud must have:
- All the same layer directories the others have (e.g. if `aws/` has `network/`, `clusters/`, `nodes/`, then `azure/` and `gcp/` must too)
- A working `terraform init` for every layer (rolled up from T1.1)
- A cloud-specific README *or* a top-level README section explicitly documenting that cloud's deployment

A blueprint that ships `azure/` but only documents AWS is not actually multi-cloud — flag it. Either the cloud subdir should be removed, or it should be marked "experimental — not yet supported" in the README.

### T1.7 No plaintext credentials in committed example files

Grep `*.tfvars.example` and any committed `*.tfvars` for:
- `aviatrix_password\s*=` (must be env var `AVIATRIX_PASSWORD`)
- `aviatrix_username\s*=` (env var `AVIATRIX_USERNAME`)
- `aviatrix_controller_ip\s*=` (env var `AVIATRIX_CONTROLLER_IP`)
- AWS access keys (`AKIA[0-9A-Z]{16}`), private keys (`-----BEGIN .* PRIVATE KEY-----`)

A `CHANGE_ME` placeholder for these fields is *also* a fail — it tells users to put credentials in tfvars, which is the wrong pattern.

---

## Tier 2 — Repository standards (must pass before PR)

### T2.1 Required files per leaf

Each Terraform leaf must have:
- `main.tf`
- `variables.tf` (or no variables at all — flag if `variables.tf` exists but is empty)
- `outputs.tf` (must be non-empty if any other layer reads from this layer's `terraform_remote_state`)
- `versions.tf` with a `terraform` block declaring `required_version` and pinned `required_providers`. Inline provider blocks in `main.tf` count, but a separate `versions.tf` is preferred and required for new submissions.
- `data.tf` if the leaf reads any `terraform_remote_state` (style preference, but enforced).

### T2.2 `terraform.tfvars.example` placement

- Single-layer blueprint: required at blueprint root.
- Multi-layer blueprint: required either at blueprint root **or** in each layer that has variables without defaults. Prefer per-layer.
- Multi-cloud blueprint: required at each cloud root (`aws/`, `azure/`, `gcp/`) at minimum.
- Every variable without a default must appear in some example file with a sensible placeholder.

### T2.3 Architecture diagram

Blueprint root must contain `architecture.svg` or `architecture.png`. The README must reference it via markdown image syntax.

### T2.4 README required sections (per `docs/blueprint-standards.md`)

- Title + 1-paragraph overview
- Architecture (with embedded diagram + brief explanation)
- Prerequisites (tools with version, IAM/permissions, env vars, verification commands)
- Resources Created (table with cost notes)
- Deployment instructions — copy-pasteable, with `cd` orientation, in **layer order** for multi-layer, **per-cloud** for multi-cloud
- Test scenarios (at least 1, ideally 3+)
- Cleanup / destroy instructions in **reverse order** for multi-layer
- Troubleshooting (at least 3 distinct symptom→fix entries)
- Variables reference table
- Outputs reference table
- Tested-with version table (Terraform, providers, K8s/cloud-service versions)

A multi-cloud blueprint where the deployment, test, and cleanup sections only cover one cloud fails T2.4 even if every section header exists.

### T2.5 Variable & output documentation

- Every `variable` block has a non-empty `description`
- Every `output` block has a non-empty `description`
- Outputs containing `password`, `key`, `token`, `cert`, `kubeconfig`, gateway names/IPs, or anything resembling credentials must have `sensitive = true`

```bash
grep -rEn '^variable "' "$LEAF" --include='*.tf' -A 3
grep -rEn '^output "' "$LEAF" --include='*.tf' -A 5
```

### T2.6 Naming consistency

- Resources use `var.name_prefix` or `local.name_prefix`. Flag string-literal names like `"my-transit"`.
- Blueprint directory name: lowercase-with-hyphens, no underscores or capitals.

### T2.7 No hardcoded regions / AZs / instance types when a variable exists

Grep for `region\s*=\s*"`, `instance_size\s*=\s*"`, `availability_zone\s*=\s*"`, `machine_type\s*=\s*"` in `*.tf` (not modules). If a corresponding variable exists in `variables.tf` but isn't being used, flag it. (Catches the `region = "us-east-2"` hardcode in `k8s-prod-nonprod-hybrid`.)

### T2.8 `.gitignore` hygiene

Blueprint must have a `.gitignore` that excludes `*.tfstate`, `*.tfstate.*`, `*.tfvars` (but NOT `*.tfvars.example`), `.terraform/`, `crash.log`. Verify no `*.tfstate` or `*.tfvars` (without `.example`) is currently tracked:

```bash
( cd "$BP" && git ls-files | grep -E '(\.tfstate$|\.tfstate\.|^[^/]*\.tfvars$)' )
```

---

## Tier 3 — Quality (advisory, warn but don't fail)

### T3.1 README depth
Gold standard is ~1,300 lines. A README under ~300 lines for a multi-layer blueprint is almost certainly missing something — warn.

### T3.2 Cost estimate
Resources Created table mentions hourly or monthly cost? If not, warn.

### T3.3 Tested-with table
Lists explicit Terraform, provider, and K8s versions? If absent or generic ("latest"), warn.

### T3.4 `terraform fmt -check -recursive`
Style only, advisory. Run from blueprint root.

### T3.5 Default tags / common labels
AWS provider has `default_tags`? Azure resources have `tags`? GCP has `labels`? If completely absent, warn.

### T3.6 ExternalDNS / orphan-resource cleanup notes
If the blueprint deploys ExternalDNS, ALB Controller, or anything that creates cloud resources outside Terraform's view (Route53 records, ALBs from Ingress, etc.), the cleanup section should call out the orphan-prevention steps. If not, warn.

---

## Output format

```
Blueprint: <name>
Path: <abs-path>
Shape: <single-layer | multi-layer | multi-cloud × multi-layer>
Leaves discovered: <N>
  - aws/network
  - aws/clusters/team-a
  - ...

═══════════════════════════════════════════════════
VERDICT: 🚫 BLOCKED  (or ⚠️ NEEDS WORK / ✅ READY FOR QA)
═══════════════════════════════════════════════════

Tier 1 — Deployment Blockers
  T1.1 terraform init -backend=false ............... ❌ FAIL
       └─ azure/clusters/shared: module not found at ../../../../azure-aks-multicluster/modules/aks-cluster
       └─ gcp/clusters/shared:   module not found at ../../../../gcp-gke-multicluster/modules/gke-cluster
  T1.2 terraform validate .......................... ⊘ skipped (T1.1 failed)
  T1.3 module source paths resolve ................. ❌ FAIL (2 unresolved)
  T1.4 remote_state paths resolve .................. ✅ pass
  T1.5 required vars satisfiable ................... ❌ FAIL
       └─ gcp/nodes/prod: cluster_endpoint, cluster_ca_certificate, cluster_id required but
          not in tfvars.example and not pulled from terraform_remote_state.cluster
  T1.6 multi-cloud parity .......................... ❌ FAIL
       └─ azure/ and gcp/ exist but README only documents aws/
  T1.7 no plaintext creds in examples .............. ❌ FAIL
       └─ azure/terraform.tfvars.example:10  aviatrix_password = "CHANGE_ME"

Tier 2 — Repository Standards
  T2.1 required files per leaf ..................... ❌ FAIL
       └─ aws/clusters/{prod,nonprod}: missing versions.tf
       └─ azure/nodes/prod: missing outputs.tf
  T2.2 tfvars.example placement .................... ⚠️
  T2.3 architecture diagram ........................ ❌ FAIL (no architecture.svg/png)
  T2.4 README sections ............................. ❌ FAIL
       └─ Missing: Troubleshooting, Cost estimates, Tested-with table
       └─ Multi-cloud claim with single-cloud deployment instructions
  T2.5 variable/output descriptions ................ ⚠️
       └─ azure/clusters/shared: 12 of 14 outputs missing description
  T2.6 naming consistency .......................... ✅
  T2.7 hardcoded regions/AZs/instance types ........ ❌ FAIL
       └─ aws/nodes/prod/main.tf:18  region = "us-east-2"
  T2.8 .gitignore hygiene .......................... ✅

Tier 3 — Quality (advisory)
  T3.1 README depth (189 lines) .................... ⚠️ thin
  T3.2 cost estimate ............................... ⚠️ missing
  T3.3 tested-with table ........................... ⚠️ missing
  T3.4 terraform fmt -check ........................ ✅
  T3.5 default tags/labels ......................... ⚠️ inconsistent across clouds
  T3.6 orphan-resource cleanup notes ............... n/a

───────────────────────────────────────────────────
Required to unblock QA:
  1. Fix or remove the broken Azure/GCP module references (T1.1)
  2. Either pull cluster outputs from remote_state OR document required -var inputs (T1.5)
  3. Either remove azure/ and gcp/ subdirs OR add per-cloud deployment docs (T1.6)
  4. Move Aviatrix credentials to env vars; remove from tfvars.example (T1.7)
  5. Add versions.tf to every layer (T2.1)
  6. Add architecture.svg/png and reference it from README (T2.3)
  7. Add Troubleshooting / Cost / Tested-with sections (T2.4)
  8. Replace hardcoded region with var.aws_region (T2.7)

Recommendations:
  • Expand README to cover full deployment narrative (T3.1)
  • Add cost estimate table (T3.2)
  ...

═══════════════════════════════════════════════════
VERDICT: 🚫 BLOCKED  —  do not submit to QA
═══════════════════════════════════════════════════
```

---

## Instructions for Claude

1. **Detect shape first.** Don't assume single-layer. Don't assume single-cloud. Use `Glob`/`ls` to enumerate cloud subdirs and leaves. Print the discovered shape so the user can see you parsed it correctly.

2. **Run Tier 1 to completion before reporting.** Do not stop at the first failure — collect all failures so the user gets the full punch list. Run `terraform init -backend=false` in every leaf even if some early leaves fail.

3. **Tier 2 and Tier 3 should run regardless of Tier 1 outcome.** A blueprint with 5 T1 failures and 8 T2 failures should report all 13. Don't gate higher tiers behind lower tiers.

4. **Cite line numbers.** Every failure must point to a file path, and a line number when one applies. The point of this skill is to give the submitter a concrete punch list, not a vague "needs work."

5. **Verdict is mechanical.** Any T1 fail = `🚫 BLOCKED`. All T1 pass + any T2 fail = `⚠️ NEEDS WORK`. All T1+T2 pass = `✅ READY FOR QA` (Tier 3 warnings are advisory only). Do not soften the verdict because the submitter is well-meaning.

6. **Don't mutate the blueprint.** This skill is read-only. If the user asks you to fix issues, that's a follow-up — finish the report first, then ask whether to proceed with fixes.

7. **Reference the gold standard.** When something is missing, point at the equivalent in `aws-eks-multicluster/` so the submitter has a concrete example to copy from.

## Reference: gold standard

`blueprints/aws-eks-multicluster/` is the QA-validated reference. When in doubt about whether something is required or merely nice-to-have, check whether the gold standard has it. If it does and the submission doesn't, that's at least a Tier 2 finding.

Specifically valuable to point at:
- `aws-eks-multicluster/README.md` — section structure, troubleshooting depth, cost table
- `aws-eks-multicluster/network/` — modules dir, locals usage, sensitive outputs
- `aws-eks-multicluster/clusters/frontend/data.tf` — canonical `terraform_remote_state` pattern
- `aws-eks-multicluster/.gitignore` — minimum gitignore content
