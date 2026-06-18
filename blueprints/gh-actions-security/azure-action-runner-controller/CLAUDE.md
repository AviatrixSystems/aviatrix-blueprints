# CLAUDE.md — Azure ARC Blueprint

## What this blueprint does

Deploys ARC (Actions Runner Controller) on AKS in an Azure spoke VNet. All pod egress routes through an Aviatrix spoke gateway (SNAT). DCF policy controls what pods can reach — runner pods, TLS-probe pod, and ARC system pods each have their own k8s-type SmartGroup and targeted rules.

Provider version: aviatrix `~> 8.2`. Controller: `<your-controller-ip-or-fqdn>`.

---

## Architecture

```
AKS pods (arc-runners / arc-tls-probe / arc-systems namespaces)
  │  Azure CNI — each pod gets a real VNet IP (10.10.30.128/25)
  │  ip-masq-agent patched to disable SNAT (Terraform patches the ConfigMap)
  ▼
Aviatrix spoke GW (10.10.30.0/26) — SNAT to public IP
  ▼
DCF policy list (global, <your-controller-ip-or-fqdn>)
  prio 5   PERMIT arc-systems → GitHub FQDNs (TCP 443)
  prio 10  DENY   runner-pods → ThreatIQ feed
  prio 20  PERMIT runner-pods → GitHub FQDNs (TCP 443)
  prio 25  PERMIT tls-probe   → ipinfo.io/json (DECRYPT_ALLOWED + TLS_REQUIRED)
  prio 30  PERMIT runner-pods → tool_call_fqdns (TCP 80/443)
  prio 40  PERMIT runner-pods → APT/registry FQDNs (TCP 80/443)
  prio 50  DENY+watch runner-pods → All-Web (TCP 80/443)  ← toggle watch off to enforce
```

Two always-on probe pods validate policy continuously:
- `ipify-probe` (arc-runners ns) → `https://www.example.com` — SNI rule prio 30
- `tls-probe` (arc-tls-probe ns) → `https://ipinfo.io/json` — URL+decrypt rule prio 25

---

## Prerequisites (manual, before first apply)

On the Aviatrix controller, enable via Settings → Feature Configuration:
- **Distributed Cloud Firewall** (microseg) → Enabled
- **Kubernetes** → Enabled
- **K8s DCF Policies** (auto-policy) → **Disabled** (blueprint manages policies via Terraform)

These are controller-wide and not managed by Terraform to avoid disrupting other deployments.

Also required: AKS Cluster User Role assigned to the Aviatrix SP (`var.aviatrix_sp_object_id`) on the AKS cluster — assigned automatically by `azurerm_role_assignment.aviatrix_aks_cluster_user`.

---

## Credentials

```bash
export TF_VAR_aviatrix_controller_ip="<your-controller-ip-or-fqdn>"
export TF_VAR_aviatrix_username="admin"
export TF_VAR_aviatrix_password="<password>"
```

Never put credentials in tfvars. Access credentials only via env vars or `grep` when needed for API calls.

---

## Key variables (tfvars)

| Variable | Notes |
|---|---|
| `azure_subscription_id` | Azure subscription |
| `aviatrix_account_name` | Aviatrix-side Azure account name |
| `aviatrix_sp_object_id` | Object ID of the Aviatrix Azure service principal |
| `location` | Azure region, singleword (e.g. `westeurope`) |
| `github_repo_url` | ARC scale set registration repo URL |
| `github_pat` | PAT with repo scope; must be SSO-authorized for SAML orgs |
| `arc_runner_name` | `runs-on:` label for workflows (default `azure-arc`) |
| `tool_call_fqdns` | Extra FQDNs allowed at prio 30 (e.g. `["www.example.com"]`) |
| `aviatrix_mitm_ca_pem` | PEM of Aviatrix MITM CA — required for `deploy_probes=true` |
| `deploy_probes` | Set `false` to skip probe pods on first deploy, add later |

---

## Deployment

```bash
cd azure-action-runner-controller
terraform init
terraform plan -out=tfplan   # review ~30 resources
terraform apply tfplan        # background — spoke GW takes 5–10 min
```

ARC scales to 0 when idle — no runner pod in GitHub until a job is queued. That is expected. First job takes ~30 s longer (pod spin-up).

---

## Known errors and fixes

### `CA_bundle_id is required when certificate_validation is not disabled`
`aviatrix_dcf_tls_profile` with `CERTIFICATE_VALIDATION_ENFORCE` requires `ca_bundle_id`. Use the default bundle UUID: `def000ad-6000-0000-0000-000000000002`.

### `aviatrix_distributed_firewalling_policy_list` fails — conflicting ruleset
Another policy list already attached at `TERRAFORM_BEFORE_UI_MANAGED`. Remove it from the controller first, then re-apply.

### Helm release timeout (arc_controller, 2 min)
AKS wasn't fully ready. Retry: `terraform apply` again without changes.

### k8s/helm providers connect to `localhost:80` during destroy
AKS already deleted before Terraform tries to destroy k8s resources. Fix: `terraform state rm` all k8s/helm resources first (see Destroy section).

### SmartGroup delete fails — `present in one or more dfw policies`
Remove policy list first: `terraform apply -target=aviatrix_distributed_firewalling_policy_list.runner` to drop the reference, then full apply.

### `aviatrix_smart_group` already exists on controller
Import it: `terraform import aviatrix_smart_group.<name> <uuid>`.

### `urlfilter` with `https://` scheme
Controller rejects the scheme. Use `urlfilter = "ipinfo.io/json"` (no `https://`).

### `fqdn` + `type` together in SmartGroup match_expression
`fqdn` match expression cannot have other qualifiers. Remove `type = "dns"`, use `fqdn = "hostname"` alone.

---

## TLS decryption (prio 25 rule)

- `decrypt_policy = "DECRYPT_ALLOWED"` — the only value that works in provider 8.2 (PERMIT_DECRYPT and DEEP_PACKET_INSPECTION_PERMIT are rejected by both provider and controller)
- `flow_app_requirement = "TLS_REQUIRED"` — required alongside DECRYPT_ALLOWED in 8.2
- WebGroup must use `urlfilter` (not `snifilter`) — URL-path matching is what forces GW to decrypt the TLS session
- The TLS probe pod mounts the Aviatrix MITM CA cert (`var.aviatrix_mitm_ca_pem`) so curl trusts the GW-resigned certificate

Fetch the MITM CA once:
```bash
TOKEN=$(curl -sk -X POST "https://<your-controller>/v1/api" \
  -d "action=login&username=admin&password=<pw>" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['CID'])")
curl -sk "https://<your-controller>/v2.5/api/mitm/ca" -H "Authorization: cid $TOKEN"
```

---

## TLS profile

`aviatrix_dcf_tls_profile.strict` — applied to every rule with a `web_groups` argument:
- `verify_sni = true`
- `ca_bundle_id = "def000ad-6000-0000-0000-000000000002"` (default bundle, required when certificate_validation is not disabled)
- `certificate_validation = "CERTIFICATE_VALIDATION_ENFORCE"`

---

## DCF rule 50 — watch vs enforce

`watch = true` → DENY+watch (log but allow through — phase 1 of the demo).
`watch = false` → hard DENY (silent drop — phase 2).

Default in code: `watch = false`. For the demo, change to `watch = true`, apply, run workflow (exfil succeeds), then change back to `false` and apply.

Toggle via CoPilot UI (no Terraform redeploy needed) or by editing `dcf.tf` and applying `-target=aviatrix_distributed_firewalling_policy_list.runner`.

---

## Check probe logs

```bash
az aks get-credentials \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw aks_cluster_name)

kubectl logs -n arc-runners deployment/ipify-probe --tail=10
kubectl logs -n arc-tls-probe deployment/tls-probe --tail=10
```

`ipify-probe` should print `HH:MM:SS OK`. `tls-probe` should print JSON with `"ip"` in an Azure/Microsoft range (confirms SNAT + decryption working).

---

## Trigger the exfil test workflow

```bash
PAT=$(grep github_pat terraform.tfvars | cut -d'"' -f2)
REPO=$(grep github_repo_url terraform.tfvars | cut -d'"' -f2 | sed 's|https://github.com/||')

curl -sS -X POST \
  -H "Authorization: Bearer $PAT" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}/actions/workflows/test-pii-exfil-arc.yml/dispatches" \
  -d '{"ref":"main","inputs":{"webhook_url":"https://webhook.site/<uuid>","retries":"3"}}'
```

Poll run status:
```bash
curl -sS -H "Authorization: Bearer $PAT" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}/actions/runs?per_page=3" | \
  python3 -c "import json,sys; [print(r['id'], r['name'][:40], r['status'], r['conclusion'] or '') for r in json.load(sys.stdin)['workflow_runs'][:3]]"
```

---

## Destroy

k8s/helm providers can't connect to a deleted AKS cluster — state rm first:

```bash
terraform state rm helm_release.arc_controller
terraform state rm helm_release.arc_runner_scaleset
terraform state rm kubernetes_namespace.tls_probe[0]
terraform state rm kubernetes_secret.aviatrix_ca[0]
terraform state rm kubernetes_deployment.tls_probe[0]
terraform state rm kubernetes_deployment.ipify_probe[0]
terraform state rm kubernetes_config_map.disable_snat
terraform state rm kubernetes_annotations.restart_masq_agent

terraform destroy
```

---

## Built-in UUIDs (same on all controllers)

| Resource | UUID |
|---|---|
| Public Internet SmartGroup | `def000ad-0000-0000-0000-000000000001` |
| AllWeb WebGroup | `def000ad-0000-0000-0000-000000000002` |
| ThreatIQ SmartGroup | `def05854-4100-0000-0000-000000000000` |
| Default CA bundle | `def000ad-6000-0000-0000-000000000002` |
| Log profile (session-start) | `def000ad-7000-0000-0000-000000000001` |
