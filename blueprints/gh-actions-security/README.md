# Github Actions - Secure AWS and Azure self-hosted runners

> **Claude-optimized deployment:** This blueprint is designed to be deployed end-to-end by Claude Code. Claude can run every Terraform step, monitor provisioning, manage the agent lifecycle, and execute the DCF data-exfiltration demo without any manual intervention. Optionally, add the Aviatrix MCP server to let Claude query live DCF logs, inspect firewall rules, and run network diagnostics directly from the conversation. See the [Deploying with Claude Code](#deploying-with-claude-code) section below.

Single blueprint with two cloud deployments: an Azure self-hosted runner and
an AWS self-hosted runner. Both route all egress through an Aviatrix spoke
gateway (SNAT) and enforce a DCF FQDN allow-list, blocking everything that
is not explicitly permitted.

## Architecture

<p align="center">
  <img src="architecture.svg" alt="Aviatrix spoke gateway egress control diagram" width="100%">
</p>

**Traffic flow (both clouds):** Runner VM/EC2 → Aviatrix spoke GW → SNAT to GW public IP → Internet.

**Controls:**
- Egress locked down by Aviatrix DCF: explicit PERMIT rules for GitHub Actions FQDNs, Ubuntu APT, and tool-call FQDNs. Everything else hits `deny-*-unmatched-web` (DENY+watch by default — observe without enforce, flip to hard DENY via CoPilot UI).
- No changes needed in Terraform to toggle enforcement — CoPilot UI only.

## Blueprints

| Blueprint | Cloud | Purpose | Guide |
|---|---|---|---|
| [`azure-self-hosted-runner/`](azure-self-hosted-runner/) | Azure | GitHub Actions self-hosted runner in Azure spoke VNet | [README](azure-self-hosted-runner/README.md) · [TESTING](azure-self-hosted-runner/TESTING.md) |
| [`aws-self-hosted-runner/`](aws-self-hosted-runner/) | AWS | Same controls on AWS spoke VPC (EC2 runner) | [README](aws-self-hosted-runner/README.md) · [TESTING](aws-self-hosted-runner/TESTING.md) |

## Deploy

Each blueprint is self-contained. Both require Aviatrix controller credentials
as `TF_VAR_*` env vars (never in tfvars):

```bash
export TF_VAR_aviatrix_controller_ip=your-controller.example.com
export TF_VAR_aviatrix_username=admin
export TF_VAR_aviatrix_password=...
```

### Azure

```bash
cd azure-self-hosted-runner
cp terraform.tfvars.example terraform.tfvars
# edit: azure_subscription_id, aviatrix_account_name, location, github_pat, admin_password
terraform init && terraform apply
```

### AWS

```bash
cd aws-self-hosted-runner
cp terraform.tfvars.example terraform.tfvars
# edit: aws_region, aviatrix_account_name, github_repo_url, github_pat
terraform init && terraform apply
```

## Test (PII exfiltration simulation)

**Workflow:** Actions → **Test PII Exfiltration (self-hosted runners)** → select `azure` or `aws` → provide a [webhook.site](https://webhook.site) URL.

**What it does:**
1. Fetches MOTD from `www.example.com` — permitted by DCF rule 30.
2. POSTs fake PII (SSN, CC, email) to your webhook — passes while rule 50 is DENY+watch, blocked after you switch to hard DENY via CoPilot.

See per-cloud `TESTING.md` for the full step-by-step guide.

## Cleanup

```bash
# Azure
cd azure-self-hosted-runner && terraform destroy

# AWS
cd aws-self-hosted-runner && terraform destroy
```

