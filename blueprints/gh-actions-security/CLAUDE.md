# CLAUDE.md — Github Actions: Secure AWS and Azure Self-Hosted Runners

This file guides Claude Code when working in this repository. Claude can
deploy this blueprint end-to-end — provisioning infrastructure, registering
runners, running the DCF data-exfiltration demo, and tearing down — without
any manual intervention.

---

## Repository Purpose

Terraform blueprints that deploy GitHub Actions self-hosted runners on AWS
(EC2) and Azure (VM) with all egress forced through an Aviatrix spoke gateway.
An Aviatrix Distributed Cloud Firewall (DCF) allow-list controls what the
runner can reach. A companion GitHub Actions workflow simulates a PII
exfiltration attack (supply-chain compromise scenario) to validate the controls.

---

## Architecture Overview

```
GitHub Actions Runner (EC2 / Azure VM)
         │
         ▼  all egress via SNAT
  Aviatrix Spoke Gateway ──────────► Internet
         │
         ▼  policy enforced by
  Aviatrix DCF Global Policy List
    prio 10  DENY  threat-iq
    prio 20  PERMIT github-fqdns    TCP 443
    prio 30  PERMIT tool-call-fqdns TCP 80+443  (www.example.com)
    prio 40  PERMIT linux-apt-fqdns TCP 80+443
    prio 50  DENY+watch all-web     TCP 80+443  ← toggle to hard DENY via CoPilot
```

Two independent single-layer blueprints — one per cloud, no shared state:

| Blueprint | Cloud | Provider version |
|---|---|---|
| `azure-self-hosted-runner/` | Azure | aviatrix ~> 9.0 |
| `aws-self-hosted-runner/` | AWS | aviatrix ~> 8.2 |

---

## Environment Setup

### Aviatrix controller credentials (both blueprints)

```bash
export TF_VAR_aviatrix_controller_ip="<controller-ip-or-fqdn>"
export TF_VAR_aviatrix_username="admin"
export TF_VAR_aviatrix_password="<password>"
```

### Azure credentials

```bash
az login
# or service principal:
export ARM_CLIENT_ID=... ARM_CLIENT_SECRET=... ARM_TENANT_ID=... ARM_SUBSCRIPTION_ID=...
```

### AWS credentials

```bash
export AWS_PROFILE=<profile>
# or:
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=eu-west-2
```

---

## Deploying the Azure Blueprint

```bash
cd azure-self-hosted-runner

cp terraform.tfvars.example terraform.tfvars
# Required edits:
#   aviatrix_controller_ip → set via TF_VAR_* env var (see above)
#   azure_subscription_id, aviatrix_account_name, location
#   github_repo_url, github_pat (repo scope, SSO-authorized for the org)
#   admin_password

terraform init
terraform plan -out=tfplan   # review: ~22 resources
terraform apply tfplan
```

`terraform apply` auto-publishes `vars.GW_PUBLIC_IP` to the target GitHub
repo via `null_resource.publish_gw_ip`. The self-hosted runner registers at
VM boot via cloud-init (GitHub PAT must be SSO-authorized before apply).

**Expected time:** ~5–10 min (spoke gateway is the slowest resource).

Poll runner status after apply:
```bash
curl -sS -H "Authorization: Bearer $(grep github_pat terraform.tfvars | cut -d'"' -f2)" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/<org>/<repo>/actions/runners | python3 -c \
  "import json,sys; [print(r['name'],r['status']) for r in json.load(sys.stdin)['runners']]"
```

---

## Deploying the AWS Blueprint

```bash
cd aws-self-hosted-runner

cp terraform.tfvars.example terraform.tfvars
# Required edits:
#   aviatrix_controller_ip → set via TF_VAR_* env var
#   aws_region, aviatrix_account_name
#   github_repo_url, github_pat

terraform init
terraform plan -out=tfplan   # review: ~20 resources
terraform apply tfplan
```

`terraform apply` auto-publishes `vars.GW_PUBLIC_IP_AWS` to the target repo.

**Expected time:** ~5–8 min.

---

## Running the DCF Exfiltration Demo

The `Test PII Exfiltration (self-hosted runners)` workflow simulates two
concurrent runner behaviours:

1. **Legitimate** — MOTD fetch from `www.example.com` (should always succeed, rule 30).
2. **Malicious** — POST fake PII (SSN, CC, email) to an external webhook (passes in DENY+watch, blocked after switching to hard DENY).

### Trigger via API

```bash
PAT="<github-pat>"
WEBHOOK="https://webhook.site/<your-uuid>"
CLOUD="azure"   # or "aws"

curl -sS -X POST \
  -H "Authorization: Bearer $PAT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/<org>/<repo>/actions/workflows/test-pii-exfil.yml/dispatches \
  -d "{\"ref\":\"main\",\"inputs\":{\"webhook_url\":\"$WEBHOOK\",\"cloud\":\"$CLOUD\",\"retries\":\"3\"}}"
```

### Phase 1 — Observe (DENY+watch, default)

Initial deployment has rule 50 as `DENY + watch = true`. Traffic is **allowed
AND logged**. Check webhook.site — PII POSTs should arrive (3 requests). Check
CoPilot DCF logs → filter by SmartGroup `gh-runner-*-vm` + rule
`deny-*-unmatched-web` to see the logged attempts.

### Phase 2 — Enforce (switch to hard DENY via CoPilot)

1. CoPilot → Security → Distributed Cloud Firewall → Policy.
2. Find rule priority 50 (`deny-*-unmatched-web`).
3. Edit → Watch Mode → Off → Save.
4. Re-run the workflow — PII POST should now time out (0/3 succeed).
5. CoPilot logs show no new entries for that rule (hard drop, no watch logging).

See `azure-self-hosted-runner/TESTING.md` or `aws-self-hosted-runner/TESTING.md`
for the full step-by-step guide.

---

## Destroying Infrastructure

```bash
# Azure
cd azure-self-hosted-runner
terraform destroy

# AWS
cd aws-self-hosted-runner
terraform destroy
```

Destroy provisioners best-effort unregister the runner from GitHub. If the
runner row persists as "offline", delete it manually under
`Settings → Actions → Runners`.

**Note:** GitHub repo variables (`GW_PUBLIC_IP`, `GW_PUBLIC_IP_AWS`) are not
removed by destroy — clean up manually if rotating deployments.

---

## Key Variables

### Azure (`azure-self-hosted-runner/`)

| Variable | Required | Notes |
|---|---|---|
| `aviatrix_controller_ip` | env var | `TF_VAR_aviatrix_controller_ip` |
| `aviatrix_username` | env var | `TF_VAR_aviatrix_username` |
| `aviatrix_password` | env var | `TF_VAR_aviatrix_password` |
| `azure_subscription_id` | tfvars | |
| `aviatrix_account_name` | tfvars | Aviatrix-side Azure account |
| `location` | tfvars | singleword form e.g. `centralindia` |
| `github_repo_url` | tfvars | runner registers here |
| `github_pat` | tfvars | `repo` scope, SSO-authorized |
| `admin_password` | tfvars | VM admin password |
| `tool_call_fqdns` | tfvars | list, e.g. `["www.example.com"]` |

### AWS (`aws-self-hosted-runner/`)

| Variable | Required | Notes |
|---|---|---|
| `aviatrix_controller_ip` | env var | `TF_VAR_aviatrix_controller_ip` |
| `aviatrix_username` | env var | |
| `aviatrix_password` | env var | |
| `aws_region` | tfvars | e.g. `eu-west-2` |
| `aviatrix_account_name` | tfvars | Aviatrix-side AWS account |
| `github_repo_url` | tfvars | |
| `github_pat` | tfvars | |
| `tool_call_fqdns` | tfvars | list, e.g. `["www.example.com"]` |

---

## DCF Policy Structure

Both blueprints insert into the global Distributed Firewalling policy list via
`aviatrix_distributed_firewalling_policy_list`. Rules target the runner
SmartGroup (`gh-runner-*-vm`, matched by `gh-action=runner` tag):

| Priority | Name | Action | Notes |
|---|---|---|---|
| 10 | `deny-*-threat-group` | DENY | ThreatIQ feed — always enforced |
| 20 | `allow-*-github` | PERMIT | GitHub FQDNs TCP 443 |
| 30 | `allow-*-tool-calls` | PERMIT | `var.tool_call_fqdns` TCP 80+443 |
| 40 | `allow-*-linux-setup` | PERMIT | Ubuntu APT FQDNs TCP 80+443 |
| 50 | `deny-*-unmatched-web` | DENY+watch | Catch-all — toggle watch off to enforce |

Rule 50 starts with `watch = true` (observe without enforce). Switch watch off
via CoPilot UI to block unmatched egress — no Terraform redeploy needed.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Runner stays offline after apply | PAT not SSO-authorized for the org before apply | Authorize PAT in GitHub → Settings → Tokens → Configure SSO; then `terraform apply -replace=azurerm_linux_virtual_machine.runner` (Azure) or `terraform apply -replace=aws_instance.runner` (AWS) |
| Azure: `AVXERR-TRANSIT-0067` on spoke GW | Controller preflight — runner RT must exist before GW launch | RT is created by `azurerm_route_table.runner` + `azurerm_subnet_route_table_association.runner`; verify both are in state before the spoke |
| AWS: `publish_gw_ip` fails with 403 | PAT not SSO-authorized | Same as above — authorize PAT and `terraform apply` |
| `aviatrix_distributed_firewalling_policy_list` fails | Conflicting ruleset already attached at `TERRAFORM_BEFORE_UI_MANAGED` | Remove the existing ruleset from the controller, then re-apply |
| Exfil POST times out but MOTD succeeds | Rule 50 is hard DENY (watch=false) | Expected behavior post-phase-2. Switch back in CoPilot if needed. |
| Azure spoke GW creation errors `Gateway is in use for operation` | Concurrent apply or prior failed attempt left GW partially created | Wait 2–3 min, then `terraform plan` + `terraform apply` to retry |

---

## Notes for Claude

- **Credentials are in `terraform.tfvars`** (gitignored). Never log them. Access via `grep` only when needed for API calls.
- **Confirm before `terraform apply`** unless the user has explicitly toggled auto-apply for this session.
- **Background long operations** (`terraform apply`, `terraform destroy`) using `run_in_background=true` — spoke GW creation takes 3–10 min.
- **Background tasks lose CWD** — always chain `cd <blueprint-dir> &&` with the terraform command in a single Bash call.
- **Runner registration delay** — after `terraform apply` completes, poll the GitHub API for runner status; cloud-init typically registers the runner within 90 s.
- **PAT SSO authorization** — if the target GitHub org uses SAML, the PAT must be SSO-authorized *before* `terraform apply`. Cloud-init and `null_resource.publish_gw_ip` both use it; failures from un-authorized PAT require a VM replacement (`-replace=<resource>`).
