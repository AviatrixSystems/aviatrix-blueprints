# Agent Context: obot-mcp-egress-aws

Deploys Obot on a new EKS cluster with Aviatrix DCF enforcing per-pod FQDN egress at the network layer. No transit gateway required — the spoke gateway is the Policy Enforcement Point.

Read `README.md` for full documentation. This file provides the fast path for autonomous deployment.

## Required Variables

All variables must be set in `terraform.tfvars` before deploying.

| Variable | How to discover | Example |
|----------|----------------|---------|
| `controller_ip` | Aviatrix Controller EC2 public IP — AWS console → EC2 → search "aviatrix-controller" | `52.1.2.3` |
| `controller_password` | Controller admin password set at install time | (sensitive — never commit to git) |
| `aws_access_account` | Aviatrix Controller UI → Accounts → AWS account name (already onboarded) | `aws-prod` |
| `aviatrix_app_role_arn` | AWS IAM console → Roles → `aviatrix-role-app` → copy ARN | `arn:aws:iam::123456789012:role/aviatrix-role-app` |
| `copilot_private_ip` | CoPilot EC2 private IP — AWS console → EC2 → search "copilot" → Private IPv4 | `10.0.1.50` |
| `copilot_public_ip` | CoPilot EC2 public IP — same instance → Public IPv4 | `54.2.3.4` |
| `obot_admin_password` | Set any strong password; becomes the Obot admin credential | (sensitive — never commit to git) |

**Non-obvious optional:** `copilot_syslog_index` defaults to `9`. Verify slot 9 is free before applying: Controller UI → Settings → Logging → Remote Syslog → confirm slot 9 is empty.

## Deploy Sequence

```bash
cd blueprints/obot-mcp-egress-aws
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill all REQUIRED fields above
terraform init
terraform plan
terraform apply
# If apply fails with "clusterroles.rbac.authorization.k8s.io is forbidden" — re-run (idempotent):
terraform apply
# Update kubeconfig after apply completes:
aws eks update-kubeconfig \
  --name $(terraform output -raw eks_cluster_name) \
  --region <your-aws-region>
```

Deployment takes 20–30 minutes. EKS control plane and spoke gateway provisioning are the longest steps.

## Verification

```bash
# 1. Obot pods running
kubectl get pods -n obot-system
# Expected: obot-* pod 1/1 Running; aviatrix-network-policy-controller-* 1/1 Running

# 2. FirewallPolicy CRDs installed
kubectl get crds | grep networking.aviatrix.com
# Expected: firewallpolicies.networking.aviatrix.com and webgrouppolicies.networking.aviatrix.com

# 3. Obot API responding
kubectl port-forward -n obot-system svc/obot-obot 8080:80 &
sleep 3
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/mcp-servers
# Expected: 200
```

## Common Errors

```
Error: clusterroles.rbac.authorization.k8s.io is forbidden
Cause: EKS access entry propagation delay on first deploy
Fix: re-run terraform apply — second run succeeds (idempotent)
```

```
Error: EKS nodes NotReady / kubectl shows CSE exit 50
Cause: nodes started before spoke gateway programmed VPC route tables (bootstrap race)
Fix: terminate the stuck node instance to speed up replacement:
  aws ec2 terminate-instances --instance-ids <instance-id>
  EKS managed node group re-launches it once spoke gateway routes are in place.
  Alternatively, wait — replacement is automatic but slower.
```

```
Error: no matches for kind 'FirewallPolicy' in group 'networking.aviatrix.com'
Cause: k8s-firewall Helm release failed during apply
Fix: terraform apply -target=helm_release.aviatrix_crds
```

```
Error: cannot re-use a name that is still in use
Cause: previous terraform apply left the obot Helm release in failed state
Fix: helm uninstall obot -n obot-system && terraform apply
```

## Constraints

- `terraform apply` may need to run **twice** on first deploy due to EKS access entry propagation delay. Both runs are safe (idempotent).
- EKS node bootstrap race is self-healing. Do not manually intervene unless nodes are still NotReady after 10 minutes.
- K8s SmartGroups may show "Partial" in CoPilot until onboarding completes (~2 minutes post-deploy). Per-pod FirewallPolicy enforcement works correctly during this window.
- `obot_mcp_pod_cidrs` — leave empty. Only needed if K8s label SmartGroups remain Partial and per-pod deny enforcement is required.
- Port 31284 (OTEL) must be open inbound on the CoPilot security group from the spoke gateway public IP — required for DCF Monitor to populate.
