# Github Actions - Secure AWS and Azure self-hosted runners

> **Claude-optimized deployment:** This blueprint is designed to be deployed end-to-end by Claude Code. Claude can run every Terraform step, monitor provisioning, manage the agent lifecycle, and execute the DCF data-exfiltration demo without any manual intervention. Optionally, add the Aviatrix MCP server to let Claude query live DCF logs, inspect firewall rules, and run network diagnostics directly from the conversation. See the [Deploying with Claude Code](#deploying-with-claude-code) section below.

Four blueprints across two runner types and two clouds. All route egress through an Aviatrix spoke gateway (SNAT) and enforce a DCF FQDN allow-list — blocking everything not explicitly permitted.

## Architecture

<p align="center">
  <img src="architecture.svg" alt="Aviatrix spoke gateway egress control diagram" width="100%">
</p>

**Traffic flow (all blueprints):** Runner VM or pod → Aviatrix spoke GW → SNAT to GW public IP → Internet.

**Controls:**
- Egress locked down by Aviatrix DCF: explicit PERMIT rules for GitHub Actions FQDNs, Ubuntu APT/registries, and optional tool-call FQDNs. Everything else hits `deny-*-unmatched-web` (DENY+watch by default — observe without enforce, flip to hard DENY via CoPilot UI).
- No Terraform redeploy needed to toggle enforcement — CoPilot UI only.

## Blueprints

---

### Self-hosted VM runners

A persistent VM registers as a GitHub Actions runner at boot. SmartGroup targets the VM by cloud tag.

| Blueprint | Cloud | Guide |
|---|---|---|
| [`azure-self-hosted-runner/`](azure-self-hosted-runner/) | Azure (VM) | [README](azure-self-hosted-runner/README.md) · [TESTING](azure-self-hosted-runner/TESTING.md) |
| [`aws-self-hosted-runner/`](aws-self-hosted-runner/) | AWS (EC2) | [README](aws-self-hosted-runner/README.md) · [TESTING](aws-self-hosted-runner/TESTING.md) |

**DCF SmartGroup:** VM-tag selector (`gh-action=runner`). No TLS decryption.

---

### ARC (Actions Runner Controller) — ephemeral pods

<p align="center">
  <img src="architecture-arc.svg" alt="Aviatrix ARC runner egress control diagram" width="100%">
</p>

ARC runs on Kubernetes (AKS / EKS). Runner pods are ephemeral — spin up on demand, scale to zero when idle. SmartGroups are k8s-type (per namespace). Adds TLS decryption for URL-path-based policy enforcement.

| Blueprint | Cloud | Guide |
|---|---|---|
| [`azure-action-runner-controller/`](azure-action-runner-controller/) | Azure (AKS) | [README](azure-action-runner-controller/README.md) · [TESTING](azure-action-runner-controller/TESTING.md) |
| [`aws-action-runner-controller/`](aws-action-runner-controller/) | AWS (EKS) | [README](aws-action-runner-controller/README.md) |

**DCF SmartGroup:** k8s-type per namespace (`arc-runners`, `arc-tls-probe`, `arc-systems`). Adds prio 25 `DECRYPT_ALLOWED` rule for URL-path matching.

> **ARC prerequisite:** enable on the Aviatrix controller before first apply — Settings → Feature Configuration:
> - Distributed Cloud Firewall → **Enabled**
> - Kubernetes → **Enabled**
> - K8s DCF Policies (auto-policy) → **Disabled** (blueprint manages policies via Terraform)

---

## Prerequisites

All four leaves share a common base; ARC leaves add Kubernetes-specific requirements.

### Common (all blueprints)

| Requirement | Detail | Verify |
|---|---|---|
| Terraform | >= 1.3 | `terraform version` |
| Aviatrix Controller | Reachable; v8.2+ | `curl -sk https://$AVIATRIX_CONTROLLER_IP/v1/api` |
| Aviatrix account | Linked to the target AWS or Azure account | Aviatrix UI → Accounts |
| GitHub PAT | `repo` scope on the target repo | `curl -s -H "Authorization: Bearer $PAT" https://api.github.com/user` |
| DCF feature flag | Settings → Feature Configuration → Distributed Cloud Firewall → **Enabled** | Controller UI |

### AWS leaves (`aws-self-hosted-runner`, `aws-action-runner-controller`)

| Requirement | Detail | Verify |
|---|---|---|
| AWS CLI + credentials | Authenticated to the target account | `aws sts get-caller-identity` |

### Azure leaves (`azure-self-hosted-runner`, `azure-action-runner-controller`)

| Requirement | Detail | Verify |
|---|---|---|
| Azure CLI + credentials | Authenticated to the target subscription | `az account show` |
| Azure subscription ID | Passed via `azure_subscription_id` variable | `az account list --query "[].id"` |

### ARC leaves only (`aws-action-runner-controller`, `azure-action-runner-controller`)

| Requirement | Detail | Verify |
|---|---|---|
| Kubernetes feature flag | Settings → Feature Configuration → Kubernetes → **Enabled** | Controller UI |
| K8s DCF auto-policy | Settings → Feature Configuration → K8s DCF Policies → **Disabled** | Controller UI |
| Aviatrix MITM CA PEM | Required when `deploy_probes = true` (default); mounted into the TLS-probe pod | See leaf README for fetch instructions |

### Environment variables — never commit to tfvars

```bash
export TF_VAR_aviatrix_controller_ip=your-controller.example.com
export TF_VAR_aviatrix_username=admin
export TF_VAR_aviatrix_password=...
```

---

## Resource Inventory

Each leaf deploys its own isolated spoke environment. The table below summarizes major resources per leaf — see the leaf README for the full list.

| Resource | VM leaves (AWS / Azure) | ARC leaves (EKS / AKS) |
|---|---|---|
| VPC / VNet | 1 | 1 |
| Subnets | 1–2 | 3 (GW + primary + secondary) |
| Aviatrix spoke gateway | 1 | 1 |
| Aviatrix SmartGroups | 1 (VM-tag) | 3 (k8s per namespace) |
| Aviatrix WebGroups | 2–3 | 3–4 |
| DCF policy list | 1 | 1 |
| TLS decrypt profile | — | 1 |
| Compute (runner) | 1 EC2 / Azure VM | EKS / AKS cluster + managed node group |
| Helm releases (ARC) | — | 2 (controller + scale set) |
| Probe deployments | — | 2 (ipify-probe, tls-probe) |

---

## Variables

All leaves share the same Aviatrix credential pattern (env-var-only) and a similar variable surface. Key variables common across leaves:

| Variable | Scope | Description |
|---|---|---|
| `aviatrix_controller_ip` | All | Controller hostname — **env var only** |
| `aviatrix_username` | All | Controller username — **env var only** |
| `aviatrix_password` | All | Controller password — **env var only** |
| `aviatrix_account_name` | All | Aviatrix account mapped to the cloud account |
| `github_pat` | All | PAT with `repo` scope |
| `github_repo_url` | All | Repo URL for runner registration |
| `tool_call_fqdns` | All | Extra FQDNs for agent/tool calls (rule omitted when empty) |
| `aws_region` | AWS | AWS region |
| `azure_subscription_id` | Azure | Azure subscription |
| `location` | Azure | Azure region |
| `aviatrix_mitm_ca_pem` | ARC | PEM of Aviatrix MITM CA for TLS probe pod |
| `deploy_probes` | ARC | Deploy TLS-probe and ipify-probe pods (default `true`) |

For the complete variable list per leaf, see the leaf README.

---

## Outputs

Each leaf exports identifiers needed to verify the deployment and reference resources in workflows.

| Output | VM leaves | ARC leaves | Sensitive |
|---|---|---|---|
| `deployment_id` | ✓ | ✓ | no |
| `vpc_id` / `vnet_id` | ✓ | ✓ | no |
| `spoke_gateway_name` | ✓ | ✓ | yes |
| `spoke_gateway_public_ip` | ✓ | ✓ | yes |
| `runner_label` / `arc_runner_label` | ✓ | ✓ | no |
| `runner_smart_group_uuid` | ✓ | ✓ | no |
| `eks_cluster_name` / `aks_cluster_name` | — | ✓ | no |
| `eks_cluster_endpoint` / `aks_cluster_fqdn` | — | ✓ | no |

For the complete output list per leaf, see the leaf README.

---

## Cost Estimate

All costs are indicative (USD, monthly, based on default instance sizes).

| Leaf | Major cost drivers | Estimate |
|---|---|---|
| `aws-self-hosted-runner` | 1× spoke GW EC2 (`t3.medium`) + 1× runner EC2 (`t3.medium`) + Aviatrix license | ~$65–75 / month |
| `azure-self-hosted-runner` | 1× spoke GW VM + 1× runner VM (`Standard_B2ms`) + Aviatrix license | ~$70–85 / month |
| `aws-action-runner-controller` | 1× spoke GW EC2 + EKS control plane ($72) + 1× node (`t3.medium`) + Aviatrix license | ~$135–145 / month |
| `azure-action-runner-controller` | 1× spoke GW VM + AKS control plane (free tier) + 1× node (`Standard_D2s_v3`) + Aviatrix license | ~$100–120 / month |

ARC runner pods are ephemeral and scale to zero — no idle compute cost beyond the node group minimum. SmartGroups, WebGroups, and DCF policies are controller configuration objects with no infrastructure cost.

---

## Deploy

All blueprints require Aviatrix controller credentials as `TF_VAR_*` env vars (never in tfvars):

```bash
export TF_VAR_aviatrix_controller_ip=your-controller.example.com
export TF_VAR_aviatrix_username=admin
export TF_VAR_aviatrix_password=...
```

### Self-hosted VM runners

```bash
# Azure
cd azure-self-hosted-runner
cp terraform.tfvars.example terraform.tfvars
# edit: azure_subscription_id, aviatrix_account_name, location, github_pat, admin_password
terraform init && terraform apply

# AWS
cd aws-self-hosted-runner
cp terraform.tfvars.example terraform.tfvars
# edit: aws_region, aviatrix_account_name, github_repo_url, github_pat
terraform init && terraform apply
```

### ARC runners

```bash
# Azure ARC (AKS)
cd azure-action-runner-controller
cp terraform.tfvars.example terraform.tfvars
# edit: azure_subscription_id, aviatrix_account_name, aviatrix_sp_object_id,
#       location, github_pat, github_repo_url, aviatrix_mitm_ca_pem
terraform init && terraform apply

# AWS ARC (EKS)
cd aws-action-runner-controller
cp terraform.tfvars.example terraform.tfvars
# edit: aws_region, aviatrix_account_name, github_pat, github_repo_url, aviatrix_mitm_ca_pem
terraform init && terraform apply
```

## Security Policy Probes (ARC blueprints)

Both ARC blueprints (`azure-action-runner-controller/` and `aws-action-runner-controller/`) deploy two always-on probe pods alongside the ARC runner. They demonstrate two different DCF enforcement modes and serve as live policy validation — the same controls apply to any workflow job running on the ARC runner.

| Probe | Namespace | Target | DCF mechanism | What it shows |
|---|---|---|---|---|
| `ipify-probe` | `arc-runners` | `https://www.example.com` | Domain-name allow rule (SNI filter, prio 30) | Baseline FQDN-based egress control — traffic allowed by hostname match, no decryption needed |
| `tls-probe` | `arc-tls-probe` | `https://ipinfo.io/json` | URL-based allow rule (URL filter, prio 25) + `DECRYPT_ALLOWED` + `TLS_REQUIRED` | Deep inspection — GW decrypts the TLS session to match the full URL path, re-signs with Aviatrix CA, then re-encrypts toward the origin |

**Key point:** these are not test utilities — they mirror the policy controls that govern actual runner jobs. A workflow step that calls `curl https://www.example.com` hits the same FQDN rule as `ipify-probe`. A step that calls a URL-matched endpoint would require the same TLS decryption rule to be in place. Anything not explicitly permitted hits the catch-all `deny-*-unmatched-web` rule at prio 50.

**Expected vs blocked traffic:**
- `www.example.com` → **PERMITTED** — explicitly listed in `var.tool_call_fqdns`, matched by the FQDN allow rule at prio 30.
- `webhook.site` (or any destination not in the allow list) → **BLOCKED** — falls through to the catch-all DENY rule at prio 50. This is the supply-chain attack scenario: a compromised workflow step attempts to exfiltrate data to an attacker-controlled endpoint and is silently dropped.

Probe logs are visible in CoPilot → Security → Distributed Cloud Firewall → Logs, filtered by SmartGroup `*-runner-pods` or `*-tls-probe`.

## Test (PII exfiltration simulation)

Two workflows, one per runner type:

| Workflow | Runners | Trigger |
|---|---|---|
| **Test PII Exfiltration (self-hosted runners)** | `azure` / `aws` VM runners | Actions → select cloud |
| **Test PII Exfiltration (ARC / AKS runners)** | `azure-arc` / `aws-arc` ARC pods | Actions → select runner label |

**What both do:**
1. Fetch MOTD from `www.example.com` — permitted by DCF rule 30.
2. POST fake PII (SSN, CC, email) to your webhook — passes while rule 50 is DENY+watch, blocked after you switch to hard DENY via CoPilot.

**Result colors:** ✅ green = exfil BLOCKED (policy enforced). ❌ red = exfil SUCCEEDED (policy bypassed — security failure).

See per-blueprint `TESTING.md` for the full step-by-step guide.

## Cleanup

Self-hosted runners:
```bash
cd azure-self-hosted-runner && terraform destroy
cd aws-self-hosted-runner && terraform destroy
```

ARC blueprints — state rm required before destroy (k8s/helm providers can't connect to a deleted cluster):
```bash
# Azure ARC
cd azure-action-runner-controller
terraform state rm helm_release.arc_controller helm_release.arc_runner_scaleset \
  kubernetes_namespace.tls_probe[0] kubernetes_secret.aviatrix_ca[0] \
  kubernetes_deployment.tls_probe[0] kubernetes_deployment.ipify_probe[0] \
  kubernetes_config_map.disable_snat kubernetes_annotations.restart_masq_agent
terraform destroy

# AWS ARC
cd aws-action-runner-controller
terraform state rm helm_release.arc_controller helm_release.arc_runner_scaleset \
  kubernetes_namespace.tls_probe[0] kubernetes_secret.aviatrix_ca[0] \
  kubernetes_deployment.tls_probe[0] kubernetes_deployment.ipify_probe[0] \
  kubernetes_env.aws_node_externalsnat
terraform destroy
```

## Troubleshooting

### Common (all leaves)

| Symptom | Likely cause | Fix |
|---|---|---|
| `Missing required argument "controller_ip"` | `TF_VAR_aviatrix_*` env vars not exported | `export TF_VAR_aviatrix_controller_ip=...` etc; re-run |
| Runner never appears in GitHub Settings → Runners | PAT lacks `repo` scope, or DCF blocks GitHub FQDNs | Verify PAT scope; check WebGroup contains `github.com` + `api.github.com` |
| Terraform plan shows unexpected diff after clean apply | Aviatrix provider version drift | Pin `AviatrixSystems/aviatrix` to the version in the leaf's `versions.tf` |

### Self-hosted VM runners

| Symptom | Likely cause | Fix |
|---|---|---|
| VM provisioned but runner stays offline | `cloud-init` script failed during boot | SSH into the VM; check `/var/log/cloud-init-output.log` for PAT or connectivity errors |
| `terraform destroy` hangs on VM deletion | Runner process holding a lock | Deregister the runner in GitHub UI first, or force-remove via API |

### ARC runners (EKS / AKS)

| Symptom | Likely cause | Fix |
|---|---|---|
| Helm release timeout (`arc_controller`) | Cluster not fully ready | Retry `terraform apply` — idempotent |
| `kubectl` returns `Unauthorized` | Current identity not in cluster access entries | Add your ARN/identity to `cluster_admin_arns` (EKS) or check AKS RBAC; re-apply |
| `ipify-probe` prints `BLOCKED` | DCF rule 50 is hard DENY and prio 30 missing `www.example.com` | Verify `var.tool_call_fqdns` includes `www.example.com`; re-apply |
| `tls-probe` returns TLS errors instead of JSON | MITM CA PEM not provided or malformed | Re-fetch the CA PEM from the controller and set `aviatrix_mitm_ca_pem` correctly |
| EKS/AKS nodes can't pull images during creation | Spoke GW not up yet when node group starts | `depends_on` should prevent this; if it happens, `terraform apply` again |
| `terraform destroy` fails — k8s provider can't connect | Cluster deleted before k8s resources removed from state | Run `terraform state rm` for k8s/helm resources first, then retry destroy (see Cleanup) |

---

## Tested With

Tested versions across leaves (see each leaf README for the full provider/module matrix):

| Component | Version |
|---|---|
| Terraform | 1.7.x |
| Aviatrix Controller | 8.2.x |
| `AviatrixSystems/aviatrix` provider | 8.2.10 |
| `hashicorp/aws` | 5.100.0 |
| `hashicorp/azurerm` | 4.x |
| `hashicorp/helm` | 2.17.0 |
| `hashicorp/kubernetes` | 2.38.0 |
| `terraform-aws-modules/eks/aws` | 20.x |
| EKS Kubernetes | 1.31.x |
| AKS Kubernetes | 1.30.x / 1.31.x |
| ARC charts (`gha-runner-scale-set-controller`, `gha-runner-scale-set`) | 0.9.x |
| AWS regions validated | `eu-west-1` |
| Azure regions validated | `westeurope` |
