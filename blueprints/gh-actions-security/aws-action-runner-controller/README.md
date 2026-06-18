# Github Actions - Secure AWS ARC Runners (EKS)

Deploys GitHub Actions [Actions Runner Controller (ARC)](https://github.com/actions/actions-runner-controller) on EKS in an AWS spoke VPC with all pod egress forced through an Aviatrix spoke gateway (SNAT). An Aviatrix Distributed Cloud Firewall (DCF) ruleset permits only a tightly scoped allow-list of FQDNs (GitHub Actions infrastructure, ECR/APT/container registries, plus any optional tool-call FQDNs you opt into) on TCP 80/443. All other egress is implicitly denied.

Unlike the self-hosted VM blueprint, ARC runner pods are ephemeral and scale to zero when idle — no cost for idle capacity.

## Architecture

<p align="center">
  <img src="architecture.svg" alt="Aviatrix ARC runner egress control diagram — AWS EKS" width="100%">
</p>

**Traffic flow:** ARC runner pod → VPC CNI VPC IP → Aviatrix spoke GW → SNAT to EIP → Internet.

**Controls:**
- **Pod IP preservation:** VPC CNI assigns each pod a real VPC IP. `AWS_VPC_K8S_CNI_EXTERNALSNAT=true` is patched into the `aws-node` DaemonSet `env:` spec so pod source IPs reach the spoke gateway unmasked — required for DCF k8s SmartGroup matching.
- **Egress:** EKS private subnet route tables have `0.0.0.0/0 → Aviatrix spoke ENI`. All outbound traffic from pods passes through the spoke GW and is subject to DCF policy.
- **Deployer access:** The blueprint auto-detects the deployer's IAM role via `aws_iam_session_context` and grants EKS cluster-admin access — works for both direct IAM users and SSO/assumed-role sessions.
- **DCF policy:** 7 rules (priorities 5–50). Separate k8s-type SmartGroups per namespace allow different rules for ARC system pods, runner pods, and the TLS-decrypt probe pod.
- **TLS decryption:** A dedicated `tls-probe` pod in `arc-tls-probe` namespace validates the `DECRYPT_ALLOWED` rule — the spoke GW decrypts TLS sessions, matches the URL path against the WebGroup, then re-encrypts toward the origin.

```
EKS pods (arc-runners / arc-tls-probe / arc-systems namespaces)
  │  VPC CNI — each pod gets a real VPC IP from eks_primary_subnet_cidr
  │  AWS_VPC_K8S_CNI_EXTERNALSNAT=true in aws-node DaemonSet (pod IPs preserved)
  ▼
Aviatrix spoke GW (gw_subnet_cidr, public) — SNAT to EIP
  ▼
DCF global policy list
  prio 5   PERMIT  arc-systems  → GitHub FQDNs        TCP 443
  prio 10  DENY    runner-pods  → ThreatIQ feed        ANY
  prio 20  PERMIT  runner-pods  → GitHub FQDNs        TCP 443
  prio 25  PERMIT  tls-probe    → ipinfo.io/json       TCP 443  DECRYPT_ALLOWED
  prio 30  PERMIT  runner-pods  → tool_call_fqdns      TCP 80/443
  prio 40  PERMIT  runner-pods  → ECR / APT / registries  TCP 80/443
  prio 50  DENY+watch runner-pods → All-Web            TCP 80/443  ← toggle watch off to enforce
```

Two always-on probe pods validate policy continuously after deployment:

| Probe | Namespace | Target | DCF rule |
|---|---|---|---|
| `ipify-probe` | `arc-runners` | `https://www.example.com` | Prio 30 — SNI FQDN allow |
| `tls-probe` | `arc-tls-probe` | `https://ipinfo.io/json` | Prio 25 — URL allow + `DECRYPT_ALLOWED` |

## Prerequisites

| Requirement | Detail | Verify |
|---|---|---|
| Terraform | >= 1.3 | `terraform version` |
| AWS CLI + credentials | Authenticated | `aws sts get-caller-identity` |
| Aviatrix Controller | Reachable; v8.2+ | `curl -sk https://$AVIATRIX_CONTROLLER_IP/v1/api` |
| Aviatrix account | Linked to the target AWS account | Aviatrix UI → Accounts |
| GitHub PAT | `repo` scope on the target repo | `curl -s -H "Authorization: Bearer $PAT" https://api.github.com/user` |

### Controller feature flags (one-time, manual)

Enable in the Aviatrix controller under **Settings → Feature Configuration**:

| Feature | Setting |
|---|---|
| Distributed Cloud Firewall | Enabled |
| Kubernetes | Enabled |
| K8s DCF Policies (auto-policy) | **Disabled** — blueprint manages policies via Terraform |

### AWS credentials

```bash
export AWS_PROFILE=<profile>
# or:
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_REGION=<region>
```

### Environment variables — never commit to tfvars

```bash
export TF_VAR_aviatrix_controller_ip=your-controller.example.com
export TF_VAR_aviatrix_username=admin
export TF_VAR_aviatrix_password=...
```

### EKS cluster-admin access

The blueprint auto-detects the deployer's IAM role at apply time via `data.aws_iam_session_context.deployer.issuer_arn` and grants it EKS cluster-admin. This works for both IAM users and SSO/assumed-role sessions. For additional principals (CI roles, teammates), add them to `cluster_admin_arns` in `terraform.tfvars`.

### Aviatrix MITM CA certificate

Required when `deploy_probes = true` (the default). The TLS-probe pod mounts this CA so curl trusts the spoke GW's re-signed certificate.

Fetch once from the controller:
```bash
TOKEN=$(curl -sk -X POST "https://<controller>/v1/api" \
  -d "action=login&username=admin&password=..." \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['CID'])")
curl -sk "https://<controller>/v2.5/api/mitm/ca" -H "Authorization: cid $TOKEN"
```

Paste the PEM output into `terraform.tfvars` as `aviatrix_mitm_ca_pem`.

## Resources Created

| Resource | Count | Cost notes (USD, indicative, eu-west-1) |
|---|---|---|
| `aws_vpc` | 1 | free |
| `aws_subnet` (gw + eks_primary + eks_secondary) | 3 | free |
| `aws_internet_gateway` | 1 | free |
| `aws_route_table` (gw + eks) | 2 | free |
| `aws_iam_role` (EKS cluster + nodes) | 2 | free |
| EKS cluster (`module.eks`) | 1 | ~$72 / month (control plane) |
| EKS managed node group (`t3.medium` × 1) | 1 | ~$30–35 / month |
| `aviatrix_spoke_gateway` (`t3.medium` underlying EC2) | 1 | ~$30–35 / month + Aviatrix license |
| `aviatrix_smart_group` (runner-pods, tls-probe, arc-systems) | 3 | controller config — no infra cost |
| `aviatrix_web_group` | 3–4 | controller config — no infra cost |
| `aviatrix_dcf_tls_profile` | 1 | controller config — no infra cost |
| `aviatrix_distributed_firewalling_policy_list` | 1 | controller config — no infra cost |
| `helm_release` (arc-controller, arc-runner-scaleset) | 2 | no additional infra cost |
| `kubernetes_deployment` (ipify-probe, tls-probe) | 2 | pods run on EKS node — no separate cost |

**Indicative total: ~$135–145 / month** for the AWS side, plus your Aviatrix license cost for one spoke gateway. ARC runner pods are ephemeral — no idle cost (scales to zero).

## Deploy

```bash
cd aws-action-runner-controller

# Aviatrix creds — env vars, never in tfvars
export TF_VAR_aviatrix_controller_ip=your-controller.example.com
export TF_VAR_aviatrix_username=admin
export TF_VAR_aviatrix_password=...

# AWS creds
export AWS_PROFILE=<profile>

cp terraform.tfvars.example terraform.tfvars
# Required edits:
#   aws_region, aviatrix_account_name
#   github_pat, github_repo_url, aviatrix_mitm_ca_pem

terraform init
terraform plan -out=tfplan   # review ~30 resources
terraform apply tfplan        # spoke GW + EKS take 10–15 min
```

After apply, ARC scales to 0 — no runner pod appears in GitHub until a workflow job is queued. First job takes ~30 s for pod spin-up.

Outputs after apply:

| Output | Description | Sensitive |
|---|---|---|
| `deployment_id` | 6-digit suffix appended to every named resource | no |
| `vpc_id` | Spoke VPC ID | no |
| `eks_cluster_name` | EKS cluster name | no |
| `eks_cluster_endpoint` | EKS API server endpoint | no |
| `spoke_gateway_name` | Aviatrix spoke gateway name | yes |
| `spoke_gateway_public_ip` | GW EIP — SNAT egress IP for EKS pods | yes |
| `arc_runner_label` | `runs-on:` label for workflows | no |
| `runner_smart_group_uuid` | UUID of the DCF SmartGroup matching runner pods | no |

### Verify probes

```bash
aws eks update-kubeconfig --region <aws_region> --name $(terraform output -raw eks_cluster_name)

# ipify-probe — should print OK every 10s
kubectl logs -n arc-runners deployment/ipify-probe --tail=5

# tls-probe — should print JSON with an IP in an AWS range
kubectl logs -n arc-tls-probe deployment/tls-probe --tail=5
```

The IP returned by `tls-probe` should be an AWS-owned address — confirms SNAT via GW and TLS decryption working.

## Test Scenarios

See [TESTING.md](TESTING.md) for the full step-by-step security test guide (simulated PII exfiltration with DCF watch-mode observation, then enforcement). The TESTING.md for this blueprint mirrors the Azure ARC guide — replace `azure-arc` with `aws-arc` for the `runner_label` input.

### 1. PII exfiltration test (workflow)

The workflow [`.github/workflows/test-pii-exfil-arc.yml`](../.github/workflows/test-pii-exfil-arc.yml) runs on the ARC runner pod and:
1. Fetches a MOTD from `www.example.com` (should always succeed — rule 30).
2. POSTs fake PII to a user-supplied webhook URL (succeeds while rule 50 is DENY+watch; fails once switched to hard DENY via CoPilot).

**Trigger:** `workflow_dispatch` — select `aws-arc`, provide a [webhook.site](https://webhook.site) URL.

**Expected phase 1** (watch=true): both `www.example.com` and `webhook.site` POST succeed. PII appears on webhook.site.

**Expected phase 2** (watch=false): `www.example.com` succeeds; `webhook.site` POST times out (0/3 retries). Nothing on webhook.site.

Trigger via API:
```bash
PAT=$(grep github_pat terraform.tfvars | cut -d'"' -f2)
REPO=$(grep github_repo_url terraform.tfvars | cut -d'"' -f2 | sed 's|https://github.com/||')

curl -sS -X POST \
  -H "Authorization: Bearer $PAT" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}/actions/workflows/test-pii-exfil-arc.yml/dispatches" \
  -d '{"ref":"main","inputs":{"webhook_url":"https://webhook.site/<uuid>","runner_label":"aws-arc","retries":"3"}}'
```

### 2. TLS decryption validation (probe)

Check that `tls-probe` returns JSON from `ipinfo.io/json` — confirms the spoke GW is decrypting TLS and the URL-based WebGroup rule at prio 25 is matching:

```bash
kubectl logs -n arc-tls-probe deployment/tls-probe --tail=3
# Expected: {"ip": "x.x.x.x", "city": "...", "org": "AS16509 Amazon.com, Inc.", ...}
# IP must be AWS-owned — confirms SNAT via GW.
```

### 3. Tool-call FQDN expansion

Add a domain to `var.tool_call_fqdns`, re-apply, then confirm access from a runner job. The DCF tool-call rule at prio 30 is created only when the list is non-empty.

## Switch watch to hard DENY (phase 2)

Rule 50 starts as `DENY + watch = true`. To enforce:

1. **CoPilot** → **Security** → **Distributed Cloud Firewall** → **Policy**.
2. Find rule priority **50** (`deny-*-unmatched-web`).
3. Click **Edit** → **Watch Mode** → **Off** → **Save**.

No Terraform redeploy needed. To revert, switch Watch Mode back to **On**.

## Cleanup

k8s/helm providers cannot connect to a deleted EKS cluster — remove those resources from state first:

```bash
cd aws-action-runner-controller

terraform state rm helm_release.arc_controller
terraform state rm helm_release.arc_runner_scaleset
terraform state rm kubernetes_namespace.tls_probe[0]
terraform state rm kubernetes_secret.aviatrix_ca[0]
terraform state rm kubernetes_deployment.tls_probe[0]
terraform state rm kubernetes_deployment.ipify_probe[0]
terraform state rm kubernetes_env.aws_node_externalsnat

terraform destroy
```

After destroy, the ARC runner scale set is de-registered from GitHub automatically. If the runner row persists as "offline", delete it manually under **Settings → Actions → Runners**.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Missing required argument "controller_ip"` | `TF_VAR_aviatrix_*` env vars not exported | `export TF_VAR_aviatrix_controller_ip=...` etc; re-run |
| EKS nodes can't pull images during cluster creation | Spoke GW not up yet when EKS node group starts | The `depends_on` in `eks.tf` should prevent this; if it happens, `terraform apply` again |
| Helm release timeout (`arc_controller`) | EKS not fully ready | Retry `terraform apply` without changes — idempotent |
| `kubectl` returns `Unauthorized` after apply | Deployer ARN not in EKS access entries | The blueprint auto-adds the deployer role; if using a different terminal session with a different assumed role, add that ARN to `cluster_admin_arns` and re-apply |
| ARC runner pod never registers | PAT lacks `repo` scope, or DCF blocks GitHub FQDNs | Check PAT scope; verify `aviatrix_web_group.gh_runner_required` contains `github.com` + `api.github.com` |
| `ipify-probe` prints `BLOCKED` | DCF rule 50 is hard DENY and prio 30 missing `www.example.com` | Verify `var.tool_call_fqdns` includes `www.example.com`; re-apply |
| `terraform destroy` fails — k8s provider can't connect | EKS deleted before k8s resources removed from state | Run `terraform state rm` for k8s/helm resources, then retry destroy (see Cleanup) |

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
| `aws_region` | AWS region (e.g. `eu-west-1`, `us-east-1`) | *(required)* |
| `aviatrix_account_name` | Aviatrix account name mapped to the AWS account | *(required)* |
| `github_pat` | PAT with `repo` scope — used by ARC to register runners | *(required)* |
| `github_repo_url` | GitHub repo URL for ARC runner scale set registration | *(required)* |
| `aviatrix_mitm_ca_pem` | PEM of Aviatrix MITM CA — mounted into TLS-probe pod | `""` (required when `deploy_probes=true`) |
| `name_prefix` | Prefix for all named resources. 6-digit deployment ID auto-appended | `gh-eks-runner` |
| `spoke_gateway_name` | Aviatrix spoke GW name. When `null`, auto-derived from `name_prefix` | `null` |
| `arc_runner_name` | ARC scale set name — the `runs-on:` label in workflows | `aws-arc` |
| `deploy_probes` | Deploy TLS-probe and ipify-probe pods | `true` |
| `cluster_admin_arns` | Extra IAM ARNs for EKS cluster-admin (deployer role auto-added) | `[]` |
| `vpc_cidr` | Spoke VPC address space | `10.20.30.0/24` |
| `gw_subnet_cidr` | Aviatrix spoke GW subnet (public, single AZ) | `10.20.30.0/26` |
| `eks_primary_subnet_cidr` | Primary EKS subnet (AZ[0]) | `10.20.30.64/26` |
| `eks_secondary_subnet_cidr` | Secondary EKS subnet (AZ[1]) — required by EKS control plane | `10.20.30.128/26` |
| `spoke_gw_size` | EC2 instance type for the spoke gateway | `t3.medium` |
| `eks_node_count` | EKS managed node group size | `1` |
| `eks_node_instance_type` | EC2 instance type for EKS worker nodes | `t3.medium` |
| `eks_kubernetes_version` | Kubernetes version (`null` = EKS region default) | `null` |
| `gh_runner_required_fqdns` | FQDNs ARC + runner pods require (TCP 443) | *(GitHub Actions infra — see `variables.tf`)* |
| `tool_call_fqdns` | Extra FQDNs for agent/tool calls (TCP 80+443) | `[]` (rule omitted when empty) |

## Outputs

| Name | Description | Sensitive |
|---|---|---|
| `deployment_id` | 6-digit suffix identifying this deployment | no |
| `vpc_id` | Spoke VPC ID | no |
| `eks_cluster_name` | EKS cluster name | no |
| `eks_cluster_endpoint` | EKS API server endpoint | no |
| `spoke_gateway_name` | Aviatrix spoke gateway name | yes |
| `spoke_gateway_public_ip` | GW EIP — SNAT egress address for pods | yes |
| `arc_runner_label` | `runs-on:` label for workflows | no |
| `runner_smart_group_uuid` | UUID of the DCF SmartGroup matching runner pods | no |

## Tested With

| Component | Version |
|---|---|
| Terraform | 1.7.x |
| `hashicorp/aws` | 5.100.0 |
| `AviatrixSystems/aviatrix` | 8.2.10 |
| `hashicorp/helm` | 2.17.0 |
| `hashicorp/kubernetes` | 2.38.0 |
| `hashicorp/random` | 3.9.0 |
| `terraform-aws-modules/eks/aws` | 20.x |
| Aviatrix Controller | 8.2.x |
| EKS Kubernetes version | 1.31.x |
| ARC chart (`gha-runner-scale-set-controller`) | 0.9.x |
| ARC chart (`gha-runner-scale-set`) | 0.9.x |
| AWS region (validated) | `eu-west-1` |

---
