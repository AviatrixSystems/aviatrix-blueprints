# CLAUDE.md — Azure Self-Hosted Runner Blueprint

## What this blueprint does

Deploys a GitHub Actions self-hosted runner on an Azure VM in a spoke VNet. All egress routes through an Aviatrix spoke gateway (SNAT). DCF policy controls what the runner VM can reach.

Provider version: aviatrix `~> 9.0`. Controller: `<your-controller-ip-or-fqdn>`.

---

## Architecture

```
Runner VM (Azure VM, tag gh-action=runner)
  │  No public IP — all egress via default route → Aviatrix GW
  ▼
Aviatrix spoke GW (SNAT to public IP)
  ▼
DCF policy list (global, <your-controller-ip-or-fqdn>)
  prio 10  DENY   runner-vm → ThreatIQ feed
  prio 20  PERMIT runner-vm → GitHub FQDNs (TCP 443)
  prio 30  PERMIT runner-vm → tool_call_fqdns (TCP 80/443)
  prio 40  PERMIT runner-vm → APT FQDNs (TCP 80/443)
  prio 50  DENY+watch runner-vm → All-Web (TCP 80/443)  ← toggle watch off to enforce
```

SmartGroup targets the runner VM by Azure tag `gh-action=runner` (type=vm selector).

---

## Credentials

```bash
export TF_VAR_aviatrix_controller_ip="<your-controller-ip-or-fqdn>"
export TF_VAR_aviatrix_username="admin"
export TF_VAR_aviatrix_password="<password>"
```

Never put credentials in tfvars. Azure credentials via `az login` or ARM env vars.

---

## Key variables (tfvars)

| Variable | Notes |
|---|---|
| `azure_subscription_id` | Azure subscription |
| `aviatrix_account_name` | Aviatrix-side Azure account name |
| `location` | Azure region, singleword (e.g. `westeurope`) |
| `github_repo_url` | Runner registers here |
| `github_pat` | PAT with repo scope; must be SSO-authorized for SAML orgs |
| `admin_password` | VM admin password (enables serial console) |
| `tool_call_fqdns` | Extra FQDNs allowed at prio 30 (e.g. `["www.example.com"]`) |

---

## Deployment

```bash
cd azure-self-hosted-runner
cp terraform.tfvars.example terraform.tfvars
# edit: azure_subscription_id, aviatrix_account_name, location, github_pat, admin_password, tool_call_fqdns
terraform init
terraform plan -out=tfplan   # review ~22 resources
terraform apply tfplan        # background — spoke GW takes 5–10 min
```

Runner registers at VM boot via cloud-init (GitHub PAT fetches a fresh registration token via API at boot time). Poll runner status after apply:

```bash
PAT=$(grep github_pat terraform.tfvars | cut -d'"' -f2)
REPO=$(grep github_repo_url terraform.tfvars | cut -d'"' -f2 | sed 's|https://github.com/||')
curl -sS -H "Authorization: Bearer $PAT" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}/actions/runners" | \
  python3 -c "import json,sys; [print(r['name'], r['status']) for r in json.load(sys.stdin)['runners']]"
```

Runner is online within ~90 s of `terraform apply` completing.

---

## Known errors and fixes

### Runner stays offline after apply
PAT not SSO-authorized for the org before apply. Authorize the PAT in GitHub (Settings → Tokens → Configure SSO), then replace the VM:
```bash
terraform apply -replace=azurerm_linux_virtual_machine.runner
```

### `AVXERR-TRANSIT-0067` on spoke GW creation
Controller preflight — runner route table must exist before GW launch. Both `azurerm_route_table.runner` and `azurerm_subnet_route_table_association.runner` must be in state first. Run `terraform apply` again to retry.

### `publish_gw_ip` null_resource fails with 403
PAT not SSO-authorized. Same fix as above.

### `aviatrix_distributed_firewalling_policy_list` fails — conflicting ruleset
Remove the existing ruleset from the controller, then re-apply.

### Spoke GW creation errors `Gateway is in use for operation`
Prior failed attempt left GW partially created. Wait 2–3 min, then `terraform plan` + `terraform apply`.

---

## DCF rule 50 — watch vs enforce

`watch = true` → DENY+watch (log but allow through — phase 1 of the demo).
`watch = false` → hard DENY (silent drop — phase 2).

Default in code: `watch = true`. Change to `false` and apply, or toggle via CoPilot UI (no Terraform redeploy needed):
- CoPilot → Security → Distributed Cloud Firewall → Policy → rule prio 50 → Edit → Watch Mode Off → Save.

---

## Trigger the exfil test workflow

```bash
PAT=$(grep github_pat terraform.tfvars | cut -d'"' -f2)
REPO=$(grep github_repo_url terraform.tfvars | cut -d'"' -f2 | sed 's|https://github.com/||')

curl -sS -X POST \
  -H "Authorization: Bearer $PAT" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}/actions/workflows/test-pii-exfil.yml/dispatches" \
  -d '{"ref":"main","inputs":{"webhook_url":"https://webhook.site/<uuid>","cloud":"azure","retries":"3"}}'
```

Phase 1 (watch=true): MOTD fetch + PII POST both succeed; POST appears on webhook.site.
Phase 2 (watch=false): MOTD fetch succeeds; PII POST times out; nothing on webhook.site.

---

## Destroy

```bash
cd azure-self-hosted-runner
terraform destroy
```

Destroy provisioner best-effort unregisters the runner. If the runner row persists as "offline", delete manually under Settings → Actions → Runners.

GitHub repo variable `GW_PUBLIC_IP` is not removed by destroy — clean up manually if needed.

---

## Built-in UUIDs (same on all controllers)

| Resource | UUID |
|---|---|
| Public Internet SmartGroup | `def000ad-0000-0000-0000-000000000001` |
| AllWeb WebGroup | `def000ad-0000-0000-0000-000000000002` |
| ThreatIQ SmartGroup | `def05854-4100-0000-0000-000000000000` |
