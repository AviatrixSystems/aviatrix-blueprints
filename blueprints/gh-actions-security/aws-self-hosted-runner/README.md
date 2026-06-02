# AWS Self-Hosted Runner with Aviatrix Egress Control

Deploys a GitHub Actions self-hosted runner in an AWS spoke VPC with all egress forced through an Aviatrix spoke gateway (SNAT). An Aviatrix Distributed Cloud Firewall (DCF) ruleset permits only a tightly scoped allow-list of FQDNs (GitHub Actions infrastructure, Ubuntu package repos, plus any optional tool-call FQDNs you opt into) on TCP 80/443. All other egress is implicitly denied. AWS-flavored counterpart of [`azure-self-hosted-runner`](../azure-self-hosted-runner/).

## Architecture

<p align="center">
  <img src="../architecture.svg" alt="Aviatrix spoke gateway egress control diagram" width="100%">
</p>

> **Note:** the diagram above is the Azure-flavored topology copied verbatim as a placeholder. The architectural pattern is identical (spoke gateway + DCF FQDN allow-list + SNAT egress); the AWS equivalents are VPC ↔ VNet, IGW ↔ Azure default internet routing, security group ↔ NSG. Replace with an AWS-rendered diagram when convenient.

**Traffic flow:** Runner EC2 → Aviatrix spoke GW (in public subnet) → SNAT to GW public IP → Internet.

**Controls:**
- **Inbound:** Security group allows only VPC-CIDR inbound; everything else denied.
- **Egress:** Private subnet route table has no default Internet route. Aviatrix programs a 0.0.0.0/0 → spoke gateway ENI route once the gateway is up. The DCF ruleset on the spoke gateway enforces an FQDN allow-list per WebGroup. Anything not matching the allow rules hits the final `deny-*-unmatched-web` rule.
- **Identity:** Runner registration uses a fresh GitHub registration token generated at VM boot via the GitHub API (PAT-authenticated). Destroy-time `null_resource` unregisters the runner from GitHub best-effort.

## Prerequisites

| Requirement | Detail | Verify |
|---|---|---|
| Terraform | >= 1.3 | `terraform version` |
| AWS CLI / SDK creds | Standard provider chain: `AWS_PROFILE` env var, or `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` | `aws sts get-caller-identity` |
| Aviatrix Controller | Reachable; v8.2+ | `curl -sk https://$AVIATRIX_CONTROLLER_IP/v1/api` |
| Aviatrix account | Linked to the target AWS account | Aviatrix UI → Accounts |
| GitHub PAT | `repo` scope (full) on the target repo; SSO-authorized if the org uses SAML | `curl -s -H "Authorization: Bearer $PAT" https://api.github.com/user` |
| curl + jq on the operator's machine | Used by `null_resource.publish_gw_ip` to write the GW IP to the repo variable | `curl --version && jq --version` |

### Environment variables — never commit to tfvars

```bash
export TF_VAR_aviatrix_controller_ip=your-controller.example.com
export TF_VAR_aviatrix_username=admin
export TF_VAR_aviatrix_password=...

# AWS provider chain — pick one
export AWS_PROFILE=your-profile
# OR
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=eu-west-3
```

### GitHub repository variable (for the egress-test workflow)

The egress test asserts runner traffic egresses via the Aviatrix spoke gateway. The workflow takes the expected gateway IP from a repo variable so it doesn't need controller credentials at runtime:

| Variable | Value | Source |
|---|---|---|
| `GW_PUBLIC_IP_AWS` | Aviatrix spoke gateway public IP (AWS deployment) | Published automatically by `terraform apply` via `null_resource.publish_gw_ip` against the repo at `var.github_repo_url`. |

The workflow also accepts `gw_public_ip` as a manual `workflow_dispatch` input.

## Resources Created

| Resource | Count | Cost notes (USD, indicative, eu-west-3) |
|---|---|---|
| `aws_vpc` | 1 | free |
| `aws_internet_gateway` | 1 | free |
| `aws_subnet` (gw + runner) | 2 | free |
| `aws_route_table` | 2 | free |
| `aws_route_table_association` | 2 | free |
| `aws_security_group` | 1 | free |
| `aws_instance` (`t3.small`) | 1 | ~$15 / month |
| EBS gp3 root volume (20 GiB) | 1 | ~$2 / month |
| `aviatrix_spoke_gateway` (`t3.medium` underlying EC2) | 1 | ~$30–35 / month EC2 + Aviatrix license tier (see your Aviatrix billing) |
| Spoke GW EIP | 1 | included with EC2 while attached |
| `aviatrix_smart_group` | 1 | controller config — no infra cost |
| `aviatrix_web_group` | 2–3 | controller config — no infra cost (tool-call group is omitted when empty) |
| `aviatrix_dcf_ruleset` | 1 | controller config — no infra cost |

**Indicative total: ~$50–60/month** for the AWS side, plus your Aviatrix license cost for one spoke gateway.

## Deploy

```bash
cd aws-self-hosted-runner

# Aviatrix creds — env vars, never in tfvars
export TF_VAR_aviatrix_controller_ip=your-controller.example.com
export TF_VAR_aviatrix_username=admin
export TF_VAR_aviatrix_password=...

# AWS creds — pick one
export AWS_PROFILE=your-profile

cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: aviatrix_account_name, aws_region, github_repo_url, github_pat

terraform init
terraform apply
# terraform apply automatically publishes GW_PUBLIC_IP_AWS to the GitHub repo
# via null_resource.publish_gw_ip — no extra step required.
```

Outputs after apply:

| Output | Description | Sensitive |
|---|---|---|
| `deployment_id` | 6-digit suffix identifying this deployment | no |
| `spoke_gateway_name` | Aviatrix spoke GW name | yes |
| `spoke_gateway_public_ip` | GW public IP — the SNAT egress IP (also `vars.GW_PUBLIC_IP_AWS`) | yes |
| `runner_instance_id` | Runner EC2 instance ID | no |
| `runner_instance_private_ip` | Runner EC2 private IP | no |
| `runner_smart_group_uuid` | UUID of the DCF SmartGroup | no |

## Test Scenarios

See [TESTING.md](TESTING.md) for the full step-by-step security test guide
(simulated PII exfiltration with DCF watch-mode observation, then enforcement).

### 1. PII exfiltration test (workflow)

The workflow [`.github/workflows/test-pii-exfil.yml`](../.github/workflows/test-pii-exfil.yml) runs on the self-hosted runner and:
1. Fetches a MOTD from `www.example.com` (should always succeed — rule 30).
2. POSTs fake PII to a user-supplied webhook URL (succeeds while rule 50 is DENY+watch, fails once switched to hard DENY via CoPilot).

**Trigger:** `workflow_dispatch` — select `aws`, provide a [webhook.site](https://webhook.site) URL.

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
cd aws-self-hosted-runner
terraform destroy
```

The destroy provisioner on `null_resource.runner_unregister` best-effort removes the runner from GitHub via the API using `var.github_pat`. **Note:** if the PAT has expired, been rotated, or lost SSO authorization, the runner row will remain in the GitHub UI as "offline" — delete it manually under `Settings → Actions → Runners`. (We've observed this silently failing — `curl -sf` swallows the error.)

If destroy fails partway, common stuck resources to clean up by hand:
- Aviatrix spoke gateway (UI → Multi-Cloud Transit → Spoke Gateways)
- Orphan DCF ruleset (UI → Distributed Cloud Firewall → Rule Sets)
- VPC dependencies (ENIs, security groups left behind by Aviatrix)

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Missing required argument "controller_ip"` on plan/apply | `TF_VAR_aviatrix_*` env vars not exported in this shell | `export TF_VAR_aviatrix_controller_ip=...` etc; re-run |
| `Error: error configuring Terraform AWS Provider: no valid credential sources` | No AWS creds in shell | `export AWS_PROFILE=...` or `aws configure` |
| Runner shows offline in GitHub UI after apply | user_data failed before `./svc.sh start`. Most common cause: PAT lacks `repo` scope, isn't SSO-authorized for the org, or the runner couldn't reach `api.github.com` (FQDN not in `gh_runner_required_fqdns`) | SSM Session Manager (if instance profile attached) or EC2 console → connect → `sudo cat /var/log/cloud-init-output.log` |
| Egress test reports `IPs do not match` (runner has its own public IP) | Aviatrix didn't add the 0.0.0.0/0 route to the runner subnet's route table | Verify in the Aviatrix UI that the spoke gateway shows the spoke VPC under "Attached VPCs" and the runner subnet's route table has `0.0.0.0/0 → <gw-eni>` |
| Runner workflow fails with `Could not resolve host: <some-domain>` | The domain isn't in any allow-list WebGroup, so DCF blocks it | Add the FQDN to `var.tool_call_fqdns` (or the appropriate WebGroup) and re-apply |
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
| `aws_region` | AWS region (e.g. `eu-west-3`, `us-east-2`) | *(required)* |
| `aviatrix_account_name` | Aviatrix account name mapping to the target AWS account | *(required)* |
| `github_pat` | PAT with `repo` scope — used at VM boot to generate a runner registration token | *(required)* |
| `github_repo_url` | GitHub repo URL for runner registration | *(required)* |
| `name_prefix` | Prefix applied to all named resources. A 6-digit deployment ID is auto-appended — final names look like `gh-runner-123456-vm` | `gh-runner` |
| `spoke_gateway_name` | Aviatrix spoke gateway name. When `null`, auto-derived from `name_prefix` + deployment ID | `null` |
| `runner_instance_type` | EC2 instance type for the runner | `t3.small` |
| `aviatrix_gw_size` | EC2 instance type for the Aviatrix spoke gateway | `t3.medium` |
| `aws_key_pair_name` | Existing AWS key pair name for SSH access (optional) | `null` |
| `runner_version` | Actions runner version | `2.334.0` |
| `runner_package_hash` | SHA-256 of the runner tarball | *(matches default `runner_version`)* |
| `vpc_cidr` | VPC address space | `10.20.10.0/24` |
| `gw_subnet_cidr` | Aviatrix GW (public) subnet | `10.20.10.0/26` |
| `runner_subnet_cidr` | Runner (private) subnet | `10.20.10.64/26` |
| `gh_runner_required_fqdns` | FQDNs the runner must reach (HTTPS 443) | *(GitHub Actions infra list — see `variables.tf`)* |
| `linux_pkg_install_fqdns` | Ubuntu APT FQDNs (TCP 80+443) | *(Ubuntu archive list — see `variables.tf`)* |
| `tool_call_fqdns` | Extra FQDNs for agent/tool calls (TCP 80+443) | `[]` (rule omitted when empty) |

## Outputs

| Name | Description | Sensitive |
|---|---|---|
| `deployment_id` | 6-digit suffix identifying this deployment | no |
| `spoke_gateway_name` | Aviatrix spoke gateway name | yes |
| `spoke_gateway_public_ip` | GW public IP — the SNAT egress address | yes |
| `runner_instance_id` | Runner EC2 instance ID | no |
| `runner_instance_private_ip` | Runner EC2 private IP | no |
| `runner_smart_group_uuid` | UUID of the DCF SmartGroup matching the runner EC2 | no |

## Tested With

| Component | Version |
|---|---|
| Terraform | 1.7.x |
| `hashicorp/aws` | ~> 5.0 |
| `AviatrixSystems/aviatrix` | 8.2.x |
| `hashicorp/null` | 3.3.x |
| `hashicorp/random` | 3.9.x |
| Aviatrix Controller | 8.2.x |
| AMI | Ubuntu 22.04 LTS amd64 (Canonical `ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*`) |
| Actions runner | 2.334.0 (linux-x64) |
