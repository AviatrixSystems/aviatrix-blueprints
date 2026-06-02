# Azure Self-Hosted Runner with Aviatrix Egress Control

Deploys a GitHub Actions self-hosted runner in an Azure spoke VNet with all egress forced through an Aviatrix spoke gateway (SNAT). An Aviatrix Distributed Cloud Firewall (DCF) ruleset permits only a tightly scoped allow-list of FQDNs (GitHub Actions infrastructure, Ubuntu package repos, plus any optional tool-call FQDNs you opt into) on TCP 80/443. All other egress is implicitly denied.

## Architecture

<p align="center">
  <img src="../architecture.svg" alt="Aviatrix spoke gateway egress control diagram" width="100%">
</p>

**Traffic flow:** Runner VM → Aviatrix spoke GW → SNAT to GW public IP → Internet.

**Controls:**
- **Inbound:** NSG allows only RFC1918 inbound; everything else denied.
- **Egress:** Runner subnet route table has a `0.0.0.0/0 → None` blackhole route, then forwards via the Aviatrix GW. The DCF ruleset on the spoke gateway enforces an FQDN allow-list per WebGroup. Anything not matching the allow rules hits the final `deny-*-unmatched-web` rule.
- **Identity:** Runner registration uses a fresh GitHub registration token generated at VM boot via the GitHub API (PAT-authenticated). Destroy-time `null_resource` unregisters the runner from GitHub best-effort.

## Prerequisites

| Requirement | Detail | Verify |
|---|---|---|
| Terraform | >= 1.3 | `terraform version` |
| Azure CLI | Authenticated | `az account show` |
| Aviatrix Controller | Reachable; v8.2+ | `curl -sk https://$AVIATRIX_CONTROLLER_IP/v1/api` |
| Aviatrix account | Linked to the target Azure subscription | Aviatrix UI → Accounts |
| GitHub PAT | `repo` scope (full) on the target repo | `curl -s -H "Authorization: Bearer $PAT" https://api.github.com/user` |
| GitHub CLI (`gh`) | Installed on the operator's machine — used by `terraform apply` to publish `GW_PUBLIC_IP` | `gh --version` |

### Environment variables — never commit to tfvars

```bash
export TF_VAR_aviatrix_controller_ip=your-controller.example.com
export TF_VAR_aviatrix_username=admin
export TF_VAR_aviatrix_password=...
```

### GitHub repository variable (for the egress-test workflow)

The egress test asserts runner traffic egresses via the Aviatrix spoke gateway. The workflow takes the expected gateway IP from a repo variable so it doesn't need controller credentials at runtime:

| Variable | Value | Source |
|---|---|---|
| `GW_PUBLIC_IP` | Aviatrix spoke gateway public IP | Published automatically by `terraform apply` via `null_resource.publish_gw_ip`, using `var.github_pat` against the repo at `var.github_repo_url`. Requires `gh` CLI on the operator's machine. |

The workflow also accepts `gw_public_ip` as a manual `workflow_dispatch` input — useful when re-validating without re-running terraform.

## Resources Created

| Resource | Count | Cost notes (USD, indicative, West Europe) |
|---|---|---|
| `azurerm_resource_group` | 1 | free |
| `azurerm_virtual_network` | 1 | free |
| `azurerm_subnet` (gw + runner) | 2 | free |
| `azurerm_route_table` | 2 | free |
| `azurerm_network_security_group` | 1 | free |
| `azurerm_network_interface` | 1 | free |
| `azurerm_linux_virtual_machine` (`Standard_B2s_v2`) | 1 | ~$30–35 / month |
| OS disk (`Standard_LRS`, 30 GiB) | 1 | ~$2 / month |
| `aviatrix_spoke_gateway` (`Standard_B2ms` underlying VM) | 1 | ~$60–70 / month VM + Aviatrix license tier (see your Aviatrix billing) |
| `aviatrix_smart_group` | 1 | controller config — no infra cost |
| `aviatrix_web_group` | 2–3 | controller config — no infra cost (tool-call group is omitted when empty) |
| `aviatrix_dcf_ruleset` | 1 | controller config — no infra cost |

**Indicative total: ~$95–110/month** for the Azure side, plus your Aviatrix license cost for one spoke gateway.

## Deploy

```bash
cd azure-self-hosted-runner

# Aviatrix creds — env vars, never in tfvars
export TF_VAR_aviatrix_controller_ip=your-controller.example.com
export TF_VAR_aviatrix_username=admin
export TF_VAR_aviatrix_password=...

cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: subscription, account, location, github_pat, admin_password

terraform init
terraform apply
# terraform apply automatically publishes GW_PUBLIC_IP to the GitHub repo
# via null_resource.publish_gw_ip — no extra step required.
```

Outputs after apply:

| Output | Description | Sensitive |
|---|---|---|
| `deployment_id` | 6-digit suffix identifying this deployment | no |
| `spoke_gateway_name` | Aviatrix spoke GW name | yes |
| `spoke_gateway_public_ip` | GW public IP — the SNAT egress IP | yes |
| `runner_vm_private_ip` | Runner VM private IP | no |
| `runner_smart_group_uuid` | UUID of the DCF SmartGroup | no |

> **Multi-deploy note:** the egress-test workflow reads only `vars.GW_PUBLIC_IP` (the gateway IP, not its name), so the auto-derived `spoke_gateway_name` is fine across multiple deployments. Re-publish `GW_PUBLIC_IP` after each fresh apply whose gateway gets a new public IP.



## Test Scenarios

See [TESTING.md](TESTING.md) for the full step-by-step security test guide
(simulated PII exfiltration with DCF watch-mode observation, then enforcement).

### 1. PII exfiltration test (workflow)

The workflow [`.github/workflows/test-pii-exfil.yml`](../.github/workflows/test-pii-exfil.yml) runs on the self-hosted runner and:
1. Fetches a MOTD from `www.example.com` (should always succeed — rule 30).
2. POSTs fake PII to a user-supplied webhook URL (succeeds while rule 50 is DENY+watch, fails once switched to hard DENY via CoPilot).

**Trigger:** `workflow_dispatch` — select `azure`, provide a [webhook.site](https://webhook.site) URL.

### 2. Block-list assertion (manual)

From the runner, attempt to reach a domain not in any WebGroup:

```bash
curl -m 5 -sv https://example.com 2>&1 | grep -E 'Connected|timed out|denied'
```

Expected: times out (or is denied once rule 50 is hard DENY).

### 3. Tool-call FQDN expansion

Add a domain to `var.tool_call_fqdns`, re-apply, then `curl` it from the runner. The DCF tool-call rule is created only when the list is non-empty.

## Cleanup

```bash
cd azure-self-hosted-runner
terraform destroy
```

The destroy provisioner on `null_resource.runner_unregister` best-effort removes the runner from GitHub via the API using `var.github_pat`. **Note:** if the PAT has expired or been rotated, the runner row will remain in the GitHub UI as "offline" — delete it manually under `Settings → Actions → Runners`.

If destroy fails partway, common stuck resources to clean up by hand:
- Aviatrix spoke gateway (UI → Multi-Cloud Transit → Spoke Gateways)
- Orphan DCF ruleset (UI → Distributed Cloud Firewall → Rule Sets)

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Missing required argument "controller_ip"` on plan/apply | `TF_VAR_aviatrix_*` env vars not exported in this shell | `export TF_VAR_aviatrix_controller_ip=...` etc; re-run |
| Runner shows offline in GitHub UI after apply | Cloud-init failed before `./svc.sh start`. Most common cause: PAT lacks `repo` scope, or the runner couldn't reach `api.github.com` (FQDN not in `gh_runner_required_fqdns`) | Serial-console into the VM (Azure Portal → VM → Serial Console, login as `azureuser`), `sudo cat /var/log/cloud-init-output.log` |
| Egress test reports `IPs do not match` | Either (a) DCF policy didn't attach, so traffic bypasses the GW; or (b) NSG default outbound rule still permits direct internet egress | Verify gateway exists in Aviatrix UI and the ruleset is attached to `TERRAFORM_BEFORE_UI_MANAGED`. Confirm `default_outbound_access_enabled = false` on the runner subnet |
| Runner workflow fails with `Could not resolve host: <some-domain>` | The domain isn't in any allow-list WebGroup, so DCF blocks it before DNS resolves through the SNAT path | Add the FQDN to `var.tool_call_fqdns` (or the appropriate WebGroup) and re-apply |
| `terraform apply` errors: `Could not find Location ...` from `data.azurerm_location` | `var.location` is not a valid Azure region singleword | Use the canonical singleword form (e.g. `westeurope`, `eastus2`, `centralindia`) — see `az account list-locations -o table` |
| `terraform destroy` hangs on the spoke gateway | DCF ruleset still references it | Detach the ruleset first via Aviatrix UI, then re-run destroy |

## Variables

Aviatrix controller credentials are passed via env vars only — never in `terraform.tfvars`:

```bash
export TF_VAR_aviatrix_controller_ip=...
export TF_VAR_aviatrix_username=...
export TF_VAR_aviatrix_password=...
```

| Name | Description | Default |
|---|---|---|
| `aviatrix_controller_ip` | Controller hostname (no `https://`) — **env var only** | *(required)* |
| `aviatrix_username` | Controller username — **env var only** | *(required)* |
| `aviatrix_password` | Controller password — **env var only** | *(required)* |
| `azure_subscription_id` | Azure subscription ID | *(required)* |
| `aviatrix_account_name` | Aviatrix account name mapping to the Azure subscription | *(required)* |
| `location` | Azure region — singleword form (e.g. `westeurope`, `eastus2`) | *(required)* |
| `github_pat` | PAT with `repo` scope — used at VM boot to generate a runner registration token | *(required)* |
| `github_repo_url` | GitHub repo URL for runner registration | *(required)* |
| `admin_password` | VM admin password (enables serial console access) | *(required)* |
| `name_prefix` | Prefix applied to all named resources. A 6-digit deployment ID is auto-appended to support multiple concurrent deployments — final names look like `gh-runner-123456-vm` | `gh-runner` |
| `spoke_gateway_name` | Aviatrix spoke gateway name. When `null`, auto-derived from `name_prefix` + deployment ID (recommended for multi-deploy) | `null` |
| `runner_version` | Actions runner version | `2.334.0` |
| `runner_package_hash` | SHA-256 of the runner tarball | *(matches default `runner_version`)* |
| `runner_vm_size` | Azure VM size | `Standard_B2s_v2` |
| `admin_username` | VM admin username | `azureuser` |
| `admin_ssh_public_key` | SSH public key for VM access | *(non-prod default included)* |
| `vnet_cidr` | VNet address space | `10.10.10.0/24` |
| `gw_subnet_cidr` | Aviatrix GW subnet | `10.10.10.0/26` |
| `runner_subnet_cidr` | Runner VM subnet | `10.10.10.64/26` |
| `gh_runner_required_fqdns` | FQDNs the runner must reach (HTTPS 443) | *(GitHub Actions infra list — see `variables.tf`)* |
| `linux_pkg_install_fqdns` | Ubuntu APT FQDNs (TCP 80+443) | *(Ubuntu archive list — see `variables.tf`)* |
| `tool_call_fqdns` | Extra FQDNs for agent/tool calls (TCP 80+443) | `[]` (rule omitted when empty) |

## Outputs

| Name | Description | Sensitive |
|---|---|---|
| `deployment_id` | 6-digit suffix identifying this deployment | no |
| `spoke_gateway_name` | Aviatrix spoke gateway name | yes |
| `spoke_gateway_public_ip` | GW public IP — the SNAT egress address | yes |
| `runner_vm_private_ip` | Runner VM private IP | no |
| `runner_smart_group_uuid` | UUID of the DCF SmartGroup matching the runner VM | no |

## Tested With

| Component | Version |
|---|---|
| Terraform | 1.7.x |
| `hashicorp/azurerm` | 3.117.1 |
| `AviatrixSystems/aviatrix` | 9.0.x |
| `hashicorp/null` | 3.3.0 |
| `hashicorp/random` | 3.9.0 |
| Aviatrix Controller | 9.0.x |
| Azure region (validated) | `westeurope` |
| VM image | Ubuntu 22.04 LTS (`Canonical / 0001-com-ubuntu-server-jammy / 22_04-lts`) |
| Actions runner | 2.334.0 (linux-x64) |

---
