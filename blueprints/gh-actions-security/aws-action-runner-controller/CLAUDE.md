# CLAUDE.md — AWS ARC Blueprint (EKS)

## What this blueprint does

Deploys ARC (Actions Runner Controller) on EKS in an AWS spoke VPC. All pod egress routes through an Aviatrix spoke gateway (SNAT). DCF policy controls what pods can reach — runner pods, TLS-probe pod, and ARC system pods each have their own k8s-type SmartGroup and targeted rules.

Provider version: aviatrix `~> 8.2`. EKS module: `terraform-aws-modules/eks/aws ~> 20.0`.

---

## Architecture

```
EKS pods (arc-runners / arc-tls-probe / arc-systems namespaces)
  │  VPC CNI — each pod gets a real VPC IP
  │  AWS_VPC_K8S_CNI_EXTERNALSNAT=true disables CNI SNAT (pod IPs preserved)
  ▼
Aviatrix spoke GW (public subnet) — SNAT to EIP
  ▼
DCF policy list (global, <your-controller-ip-or-fqdn>)
  prio 5   PERMIT arc-systems → GitHub FQDNs (TCP 443)
  prio 10  DENY   runner-pods → ThreatIQ feed
  prio 20  PERMIT runner-pods → GitHub FQDNs (TCP 443)
  prio 25  PERMIT tls-probe   → ipinfo.io/json (DECRYPT_ALLOWED + TLS_REQUIRED)
  prio 30  PERMIT runner-pods → tool_call_fqdns (TCP 80/443)
  prio 40  PERMIT runner-pods → ECR/APT/registry FQDNs (TCP 80/443)
  prio 50  DENY+watch runner-pods → All-Web (TCP 80/443)
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

AWS credentials must be configured:
```bash
export AWS_PROFILE=<profile>
# or: export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=...
```

---

## Credentials

```bash
export TF_VAR_aviatrix_controller_ip="<your-controller-ip-or-fqdn>"
export TF_VAR_aviatrix_username="admin"
export TF_VAR_aviatrix_password="<password>"
```

Never put Aviatrix credentials in tfvars.

---

## Key variables (tfvars)

| Variable | Notes |
|---|---|
| `aws_region` | AWS region (e.g. `eu-west-2`) |
| `aviatrix_account_name` | Aviatrix-side AWS account name |
| `github_repo_url` | ARC scale set registration repo URL |
| `github_pat` | PAT with repo scope; must be SSO-authorized for SAML orgs |
| `arc_runner_name` | `runs-on:` label for workflows (default `aws-arc`) |
| `tool_call_fqdns` | Extra FQDNs allowed at prio 30 (e.g. `["www.example.com"]`) |
| `aviatrix_mitm_ca_pem` | PEM of Aviatrix MITM CA — required for `deploy_probes=true` |
| `cluster_admin_arns` | Extra IAM ARNs for kubectl cluster-admin (deployer role auto-added) |
| `deploy_probes` | Set `false` to skip probe pods on first deploy |

---

## Deployment

```bash
cd aws-action-runner-controller
terraform init
terraform plan -out=tfplan   # review ~30 resources
terraform apply tfplan        # background — spoke GW + EKS take 10–15 min
```

ARC scales to 0 when idle — no runner pod in GitHub until a job is queued. First job takes ~30 s longer (pod spin-up).

---

## Key AWS/EKS differences from Azure ARC

- EKS requires subnets in **2 AZs** — two EKS subnets (`eks_primary_subnet_cidr`, `eks_secondary_subnet_cidr`) in different AZs.
- Pod IP preservation uses `AWS_VPC_K8S_CNI_EXTERNALSNAT=true` in the `amazon-vpc-cni` ConfigMap (instead of patching `azure-ip-masq-agent`).
- EKS onboarding uses `cluster_id = lower(module.eks.cluster_arn)` (ARN format, not Azure resource ID).
- `aviatrix_kubernetes_cluster` uses `use_csp_credentials = true` — controller calls AWS APIs directly via the Aviatrix AWS account.
- prio 40 WebGroup includes `*.amazonaws.com` (for ECR, S3, EKS endpoint) instead of Azure MCR FQDNs.
- EKS module from `terraform-aws-modules/eks/aws ~> 20.0` — run `terraform init` to download.

---

## Known errors and fixes

### `CA_bundle_id is required when certificate_validation is not disabled`
Use `ca_bundle_id = "def000ad-6000-0000-0000-000000000002"` in `aviatrix_dcf_tls_profile`.

### EKS nodes can't pull images / cluster creation fails
EKS nodes need to reach ECR + S3 during bootstrap — those go through the spoke GW. Verify `aviatrix_spoke_gateway.this` is up and the EKS private RT has `0.0.0.0/0 → spoke ENI` before EKS node group creation. The `depends_on` in `eks.tf` enforces this ordering.

### Helm release timeout (arc_controller, 5 min)
EKS wasn't fully ready. Retry `terraform apply` without changes.

### k8s/helm providers connect to wrong endpoint during destroy
State rm required before destroy — see Destroy section.

### `aviatrix_distributed_firewalling_policy_list` fails — conflicting ruleset
Remove existing ruleset from controller, then re-apply.

---

## TLS decryption (prio 25 rule)

Same as Azure ARC:
- `decrypt_policy = "DECRYPT_ALLOWED"` + `flow_app_requirement = "TLS_REQUIRED"`
- WebGroup uses `urlfilter = "ipinfo.io/json"` (no scheme)
- Probe pod mounts `var.aviatrix_mitm_ca_pem` so curl trusts GW-resigned cert

Fetch the MITM CA once:
```bash
TOKEN=$(curl -sk -X POST "https://<your-controller>/v1/api" \
  -d "action=login&username=admin&password=<pw>" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['CID'])")
curl -sk "https://<your-controller>/v2.5/api/mitm/ca" -H "Authorization: cid $TOKEN"
```

---

## Check probe logs

```bash
aws eks update-kubeconfig --region <region> --name $(terraform output -raw eks_cluster_name)

kubectl logs -n arc-runners deployment/ipify-probe --tail=10
kubectl logs -n arc-tls-probe deployment/tls-probe --tail=10
```

`ipify-probe` should print `HH:MM:SS OK`. `tls-probe` should print JSON with `"ip"` in an AWS range (confirms SNAT + decryption working).

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

---

## Destroy

k8s/helm providers can't connect to a deleted EKS cluster — state rm first:

```bash
terraform state rm helm_release.arc_controller
terraform state rm helm_release.arc_runner_scaleset
terraform state rm kubernetes_namespace.tls_probe[0]
terraform state rm kubernetes_secret.aviatrix_ca[0]
terraform state rm kubernetes_deployment.tls_probe[0]
terraform state rm kubernetes_deployment.ipify_probe[0]
terraform state rm kubernetes_env.aws_node_externalsnat

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
