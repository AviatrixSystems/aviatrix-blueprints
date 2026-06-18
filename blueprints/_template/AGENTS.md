# Agent Context: [blueprint-name]

<!-- TEMPLATE: Replace with 2 sentences — what deploys, what Aviatrix feature it demonstrates. -->

Brief description of what this blueprint deploys and which Aviatrix capability it demonstrates.

Read `README.md` for full documentation. This file provides the fast path for autonomous deployment.

## Required Variables

All variables must be set in `terraform.tfvars` before deploying.

<!-- TEMPLATE: List only required variables (no default value). For each, describe exactly where to find the value. -->

| Variable | How to discover | Example |
|----------|----------------|---------|
| `controller_ip` | Aviatrix Controller EC2/VM public IP — cloud console → search "aviatrix-controller" | `52.1.2.3` |
| `controller_password` | Controller admin password set at install time | (sensitive — never commit to git) |

<!-- TEMPLATE: Add a note for any optional variable with a non-obvious default that could cause deployment failures if wrong. -->

## Deploy Sequence

<!-- TEMPLATE: Exact shell commands in order. No prose between steps. Include any known multi-apply requirements. -->

```bash
cd blueprints/[blueprint-name]
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill all REQUIRED fields
terraform init
terraform plan
terraform apply
```

<!-- TEMPLATE: Replace X with a realistic estimate (e.g., 15 minutes). -->
Deployment takes approximately X minutes.

## Verification

<!-- TEMPLATE: Commands + expected output. Agent runs these to confirm success. -->

```bash
# Example format — replace with blueprint-specific checks:
# 1. Check key resource exists
terraform output -raw <output_name>
# Expected: non-empty value

# 1. [Check description]
[command]
# Expected: [what success looks like]
```

## Common Errors

<!-- TEMPLATE: Top 3-5 errors that stop autonomous agents. Use exact error strings from Terraform output or kubectl. -->

```
Error: [exact error string or pattern]
Cause: [one line]
Fix: [one line or exact command]
```

## Constraints

<!-- TEMPLATE: Timing issues, retry-safety, idempotency notes, things that look broken but aren't. -->

- [Constraint 1]
- [Constraint 2]
