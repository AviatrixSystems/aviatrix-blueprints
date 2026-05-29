# k8s-prod-nonprod-hybrid — AWS (EKS)

This blueprint deploys a production and non-production EKS environment on AWS secured by the **Aviatrix Cloud Native Security Fabric (CNSF)**. It implements two-layer Distributed Cloud Firewall (DCF) isolation: environment-level enforcement via VPC SmartGroups, and namespace-level Zero Trust segmentation via Kubernetes SmartGroups — giving teams self-service egress control through FirewallPolicy CRDs while maintaining a hard boundary between prod and nonprod.

> [!TIP]
> **Optimized for Claude Code** — Run `/deploy-blueprint` for AI-guided deployment with prerequisite checks, or `/analyze-blueprint` for resource and cost details.

<!-- TODO: Add architecture diagram -->

---

## Architecture

```
Transit GW (10.2.0.0/20, HA)
├── Prod Spoke    (10.10.0.0/20) ──── EKS prod-cluster
│                                         ├── namespace: team-a-prod
│                                         ├── namespace: team-b-prod
│                                         └── namespace: monitoring
├── NonProd Spoke (10.20.0.0/20) ──── EKS nonprod-cluster
│                                         ├── namespace: team-a-dev
│                                         ├── namespace: team-b-staging
│                                         ├── namespace: sandbox
│                                         └── namespace: monitoring
└── DB Spoke      (10.5.0.0/22)  ──── Database (prod-only)
```

See [`../architecture.svg`](../architecture.svg) for the full topology diagram.

**Two-layer DCF isolation:**

| Layer | Mechanism | Enforcement |
|---|---|---|
| Layer 1 | VPC SmartGroups | Prod VPC and NonProd VPC are bidirectionally denied. DB spoke is prod-only. |
| Layer 2 | K8s Namespace SmartGroups | Teams define egress via FirewallPolicy CRDs (priority 70–99). Controller auto-maps namespace pods to SmartGroups. |

**DCF Policy Summary:**

| Priority | Action | Rule |
|---|---|---|
| 0–1 | DENY | Geo-block (IR, KP, RU) + ThreatIQ (major/critical) |
| 10–11 | DENY | prod-vpc ↔ nonprod-vpc (bidirectional) |
| 20 | PERMIT | prod-vpc → DB spoke TCP/3306,5432 |
| 21 | DENY | nonprod-vpc → DB spoke |
| 30–31 | DENY | team-a-dev ↔ team-b-staging |
| 32 | PERMIT | monitoring → all namespaces TCP/9090-9091 |
| 50 | PERMIT | all-clusters egress HTTPS (approved registry hosts) |
| 51 | PERMIT | sandbox egress HTTPS (relaxed, all hosts) |
| 70–99 | — | Reserved: team self-service via FirewallPolicy CRDs |

---

## Prerequisites

### Aviatrix Infrastructure

| Component | Requirement | Notes |
|---|---|---|
| **Aviatrix Controller** | v8.x, provider ~> 8.2 | Must be deployed and reachable |
| **Aviatrix CoPilot** | Recommended | Required for DCF visualization and SmartGroups UI |
| **AWS Account Onboarded** | Account registered in Controller | Use exact account name as `aws_account_name` variable |

### Local Tools

| Tool | Version | Installation |
|---|---|---|
| **Terraform** | >= 1.5 | https://developer.hashicorp.com/terraform/install |
| **AWS CLI** | v2 | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |
| **kubectl** | Latest | https://kubernetes.io/docs/tasks/tools/ |
| **helm** | v3 | https://helm.sh/docs/intro/install/ |

### AWS IAM Permissions

The AWS credentials must be able to create and manage:

- **EKS**: Clusters, managed node groups, add-ons, OIDC providers
- **VPC**: VPCs, subnets, route tables, internet/NAT gateways, security groups
- **IAM**: Roles and policies (IRSA, node groups)
- **Route53**: Private hosted zones and record sets
- **EC2**: Instances, EIPs, ENIs

> **Tip:** `AdministratorAccess` works for demo environments. For production, scope the policy down.

### Quota Check

- **EIPs**: 3 VPCs × 3 AZs = ~9 NAT Gateway EIPs plus 3–6 gateway EIPs. Default quota is 5. Request an increase to **at least 20** before deploying.
- **EKS clusters**: Default is 100 per region. No increase needed for this blueprint.

### Environment Variables

```bash
# Aviatrix Controller credentials
export AVIATRIX_CONTROLLER_IP="your-controller.example.com"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="your-password"

# AWS credentials — choose one method:
# Option 1: Environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-2"

# Option 2: AWS profile
export AWS_PROFILE="your-profile"
```

---

## Resources Created

| Resource | Qty | Estimated $/hr |
|---|---|---|
| `aviatrix_transit_gateway` (c5.xlarge, HA) | 2 | ~$0.42 |
| `aviatrix_spoke_gateway` (c5.xlarge, HA each) | 6 | ~$1.26 |
| `aviatrix_vpc` | 3 | — |
| `aviatrix_distributed_firewalling_config` | 1 (if `manage_dcf=true`) | — |
| `aviatrix_k8s_config` | 1 (if `manage_dcf=true`) | — |
| `aviatrix_smart_group` | 11 | — |
| `aviatrix_web_group` | 3 | — |
| `aviatrix_dcf_ruleset` | 1 | — |
| `aws_nat_gateway` | ~9 | ~$0.45 |
| `aws_eks_cluster` | 2 | ~$0.20 |
| `aws_eks_node_group` (t3.large × 2 nodes each) | 2 | ~$0.37 |
| `aws_iam_openid_connect_provider` | 2 | — |
| `aws_iam_role` (IRSA) | 4+ | — |
| `helm_release` (ExternalDNS + k8s-firewall) | 4 | — |

**Estimated total: ~$2.70/hr** (HA enabled, us-east-2 pricing, spot not used)

> Disable HA (`enable_ha = false`) to approximately halve the Aviatrix gateway cost.

---

## Deployment Instructions

### Layer 1 — Network (~8 min)

```bash
cd aws/network

# Copy and edit the example variables file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set aws_account_name to your Aviatrix-registered account

terraform init
terraform apply
```

### Layer 2 — Clusters (parallel, ~15 min)

```bash
cd aws/clusters/prod
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set aviatrix_aws_account_name
terraform init
terraform apply &

cd ../../clusters/nonprod
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply &
wait
```

### Layer 3 — Nodes (parallel, ~8 min)

```bash
cd aws/nodes/prod
terraform init
terraform apply &

cd ../nonprod
terraform init
terraform apply &
wait
```

### Layer 4 — K8s Apps

Get cluster names from Layer 2 outputs, then apply CRDs:

```bash
# Get the cluster names
cd aws/clusters/prod
PROD_CLUSTER=$(terraform output -raw cluster_name)

cd ../nonprod
NONPROD_CLUSTER=$(terraform output -raw cluster_name)

# Configure kubectl contexts
aws eks update-kubeconfig --name $PROD_CLUSTER --alias pc2-prod --region us-east-2
aws eks update-kubeconfig --name $NONPROD_CLUSTER --alias pc2-nonprod --region us-east-2

# Apply namespace manifests
kubectl --context pc2-prod apply -f aws/k8s-apps/dcf-crd/prod-namespaces.yaml
kubectl --context pc2-nonprod apply -f aws/k8s-apps/dcf-crd/nonprod-namespaces.yaml

# Apply FirewallPolicy CRDs
kubectl --context pc2-prod apply -f aws/k8s-apps/dcf-crd/firewallpolicy-prod.yaml
kubectl --context pc2-nonprod apply -f aws/k8s-apps/dcf-crd/firewallpolicy-nonprod.yaml
```

### Update Network Layer with Cluster IDs (Two-Pass Deployment)

After clusters register with the Controller, get the Aviatrix cluster IDs and re-apply the network layer:

```bash
# Get cluster IDs from CoPilot: Security → DCF → SmartGroups → create a K8s SmartGroup
# The Controller will list available cluster IDs.

cd aws/network
# Add to terraform.tfvars:
#   prod_cluster_id   = "<id-from-copilot>"
#   nonprod_cluster_id = "<id-from-copilot>"
terraform apply
```

---

## Variables Reference

### Network (`aws/network/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `aws_account_name` | `string` | — | yes | Aviatrix AWS account name (as registered in Controller) |
| `aws_region` | `string` | `us-east-2` | no | AWS region for all resources |
| `transit_cidr` | `string` | `10.2.0.0/20` | no | Transit VPC CIDR |
| `prod_vpc_cidr` | `string` | `10.10.0.0/20` | no | Production VPC CIDR |
| `nonprod_vpc_cidr` | `string` | `10.20.0.0/20` | no | Non-production VPC CIDR |
| `db_spoke_cidr` | `string` | `10.5.0.0/22` | no | Database spoke CIDR (prod-only) |
| `pod_cidr` | `string` | `100.64.0.0/16` | no | Secondary CIDR for pod networking (VPC CNI custom networking) |
| `environment_prefix` | `string` | `pc2` | no | Prefix for all resource names |
| `transit_gw_size` | `string` | `c5.xlarge` | no | Transit Gateway instance size |
| `spoke_gw_size` | `string` | `c5.xlarge` | no | Spoke Gateway instance size |
| `db_spoke_gw_size` | `string` | `t3.medium` | no | DB Spoke Gateway instance size |
| `enable_ha` | `bool` | `true` | no | Enable HA for all gateways |
| `prod_cluster_id` | `string` | `""` | no | Aviatrix cluster ID for prod EKS (set after clusters/ deploy) |
| `nonprod_cluster_id` | `string` | `""` | no | Aviatrix cluster ID for nonprod EKS (set after clusters/ deploy) |
| `route53_zone_id` | `string` | `""` | no | Route53 hosted zone ID (creates new zone if empty) |
| `dns_domain` | `string` | `internal.example.com` | no | Base DNS domain |
| `teams` | `map(object)` | team-a, team-b | no | Team namespace configuration map |
| `random_suffix` | `bool` | `true` | no | Append random hex to resource names (prevents collisions) |
| `manage_dcf` | `bool` | `false` | no | Set `true` only if DCF is not already enabled on this Controller |

### Clusters (`aws/clusters/prod/` and `aws/clusters/nonprod/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `aviatrix_aws_account_name` | `string` | — | yes | Aviatrix access account name |
| `aws_region` | `string` | `us-east-2` | no | AWS region |
| `environment_prefix` | `string` | `pc2` | no | Resource name prefix |
| `kubernetes_version` | `string` | `1.35` | no | EKS Kubernetes version |
| `enable_private_endpoint` | `bool` | `false` | no | Disable public EKS API endpoint |
| `enable_control_plane_logging` | `bool` | `false` | no | Enable EKS control plane logging |

### Nodes (`aws/nodes/prod/` and `aws/nodes/nonprod/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| — | — | — | — | All values sourced from remote state (network + clusters layers) |

---

## Outputs Reference

| Output | Layer | Description |
|---|---|---|
| `transit_gw_name` | Network | Aviatrix Transit Gateway name |
| `prod_vpc_id` | Network | Production VPC ID |
| `prod_vpc_name` | Network | Production VPC name |
| `nonprod_vpc_id` | Network | Non-production VPC ID |
| `nonprod_vpc_name` | Network | Non-production VPC name |
| `db_vpc_id` | Network | Database spoke VPC ID |
| `prod_spoke_gw_name` | Network | Production spoke gateway name |
| `nonprod_spoke_gw_name` | Network | Non-production spoke gateway name |
| `db_spoke_gw_name` | Network | Database spoke gateway name |
| `prod_private_subnets` | Network | Production VPC private subnet IDs |
| `nonprod_private_subnets` | Network | Non-production VPC private subnet IDs |
| `dns_zone_id` | Network | Route53 zone ID |
| `sg_prod_vpc_uuid` | Network | Production VPC SmartGroup UUID |
| `sg_nonprod_vpc_uuid` | Network | Non-production VPC SmartGroup UUID |
| `sg_prod_db_uuid` | Network | Database SmartGroup UUID |
| `name_prefix` | Network | Name prefix with random suffix |
| `cluster_name` | Clusters (prod) | EKS production cluster name |
| `cluster_endpoint` | Clusters (prod) | EKS production API endpoint |
| `cluster_certificate_authority_data` | Clusters (prod) | EKS production CA certificate (base64) |
| `cluster_oidc_issuer_url` | Clusters (prod) | OIDC issuer URL for IRSA |
| `cluster_oidc_provider_arn` | Clusters (prod) | OIDC provider ARN for IRSA |
| `cluster_id` | Clusters (prod) | Aviatrix SmartGroup `k8s_cluster_id` value |
| `cluster_arn` | Clusters (prod) | EKS cluster ARN |
| `cluster_name` | Clusters (nonprod) | EKS non-production cluster name |
| `cluster_endpoint` | Clusters (nonprod) | EKS non-production API endpoint |
| `cluster_id` | Clusters (nonprod) | Aviatrix SmartGroup `k8s_cluster_id` value |

---

## Test Scenarios

### Scenario 1 — Environment Isolation (VPC Boundary)

Verify prod and nonprod VPCs are completely isolated at the network level.

```bash
# Deploy test pods in both clusters
kubectl --context pc2-prod run netshoot \
  -n default --image=nicolaka/netshoot --command -- sleep infinity --restart=Never

kubectl --context pc2-nonprod run netshoot \
  -n default --image=nicolaka/netshoot --command -- sleep infinity --restart=Never

# Get the prod pod IP
PROD_POD_IP=$(kubectl --context pc2-prod get pod netshoot -n default -o jsonpath='{.status.podIP}')

# From nonprod, attempt to reach prod — should be BLOCKED
kubectl --context pc2-nonprod exec -n default netshoot -- curl -m 5 http://$PROD_POD_IP
# Expected: curl: (28) Connection timed out — traffic BLOCKED by DCF rule priority 11
```

| Direction | Expected | DCF Rule |
|---|---|---|
| prod → nonprod VPC | BLOCKED | DENY priority 10 |
| nonprod → prod VPC | BLOCKED | DENY priority 11 |

### Scenario 2 — Database Spoke Protection (Prod-Only)

Verify the database spoke is reachable from prod but blocked from nonprod.

```bash
# Get DB instance IP from network outputs
cd aws/network
DB_IP=$(terraform output -raw db_instance_ip 2>/dev/null || echo "check terraform.tfstate")

# From prod — should SUCCEED on port 3306
kubectl --context pc2-prod exec -n default netshoot -- \
  nc -zv $DB_IP 3306 -w 5
# Expected: Connection succeeded (DCF PERMIT priority 20)

# From nonprod — should be BLOCKED
kubectl --context pc2-nonprod exec -n default netshoot -- \
  nc -zv $DB_IP 3306 -w 5
# Expected: nc: connect timeout (DCF DENY priority 21)
```

### Scenario 3 — Namespace Isolation and Team Self-Service

Verify namespace isolation within the nonprod cluster, and that FirewallPolicy CRDs apply correctly.

```bash
# Deploy test pods in nonprod namespaces
kubectl --context pc2-nonprod run netshoot-a -n team-a-dev \
  --image=nicolaka/netshoot --command -- sleep infinity --restart=Never

kubectl --context pc2-nonprod run nginx-b -n team-b-staging \
  --image=nginx:alpine --port=80 --restart=Never

TEAMB_IP=$(kubectl --context pc2-nonprod get pod nginx-b -n team-b-staging \
  -o jsonpath='{.status.podIP}')

# team-a-dev → team-b-staging should be BLOCKED (DCF DENY priority 30)
kubectl --context pc2-nonprod exec -n team-a-dev netshoot-a -- \
  curl -m 5 http://$TEAMB_IP
# Expected: timed out

# Verify monitoring scrape succeeds (PERMIT priority 32)
kubectl --context pc2-nonprod run netshoot-mon -n monitoring \
  --image=nicolaka/netshoot --command -- sleep infinity --restart=Never
kubectl --context pc2-nonprod exec -n monitoring netshoot-mon -- \
  curl -m 5 http://$TEAMB_IP:9090
# Expected: connection (or empty response) — traffic PERMITTED
```

### Scenario 4 — Sandbox Relaxed Egress

Verify the sandbox namespace has broader egress than other namespaces.

```bash
kubectl --context pc2-nonprod run netshoot-sb -n sandbox \
  --image=nicolaka/netshoot --command -- sleep infinity --restart=Never

# Sandbox can reach any HTTPS destination
kubectl --context pc2-nonprod exec -n sandbox netshoot-sb -- \
  curl -sk https://ifconfig.me
# Expected: returns public IP (sandbox-relaxed-egress WebGroup, PERMIT priority 51)

# team-a-dev cannot reach arbitrary HTTPS (only approved registry hosts)
kubectl --context pc2-nonprod exec -n team-a-dev netshoot-a -- \
  curl -sk --max-time 5 https://ifconfig.me
# Expected: timed out (only prod_approved_apis WebGroup is permitted)
```

---

## Cleanup / Destroy

Destroy in **reverse layer order**. Removing the nodes layer before clusters prevents orphaned resources.

```bash
# Layer 4: Remove K8s CRDs
kubectl --context pc2-prod delete -f aws/k8s-apps/dcf-crd/
kubectl --context pc2-nonprod delete -f aws/k8s-apps/dcf-crd/

# Layer 3: Nodes (parallel)
cd aws/nodes/prod && terraform destroy -auto-approve &
cd aws/nodes/nonprod && terraform destroy -auto-approve &
wait

# Layer 2: Clusters (parallel)
cd aws/clusters/prod
terraform destroy -var="aviatrix_aws_account_name=your-aws-account-name" -auto-approve &

cd aws/clusters/nonprod
terraform destroy -var="aviatrix_aws_account_name=your-aws-account-name" -auto-approve &
wait

# Layer 1: Network
cd aws/network
terraform destroy -var="aws_account_name=your-aws-account-name" -auto-approve
```

**Manual cleanup checklist:**

- [ ] Verify no NAT Gateways remain: `aws ec2 describe-nat-gateways --filter "Name=state,Values=available"`
- [ ] Verify no EIPs remain: `aws ec2 describe-addresses --filter "Name=domain,Values=vpc"`
- [ ] Verify EKS clusters are deleted: `aws eks list-clusters --region us-east-2`
- [ ] Verify Aviatrix resources removed: check CoPilot → Infrastructure → topology
- [ ] If `manage_dcf = true` was set: DCF will be disabled on destroy — re-enable manually if other blueprints depend on it

**Verification:**

```bash
# All Aviatrix resources should be gone
cd aws/network && terraform state list
# Expected: empty or only provider resources
```

---

## Troubleshooting

**1. Prod and nonprod can communicate after deploy**

Verify the VPC-level SmartGroups are populated. In CoPilot → Security → DCF → SmartGroups, check that `prod-vpc` and `nonprod-vpc` SmartGroups show Aviatrix gateways and node VMs. If SmartGroups are empty, the tag selector may not match. Verify the `avx:vpc-name` tag on spoke resources.

The deny rules must have priority 10 and 11 with no lower-priority (higher-number) permit rule that matches the same traffic. Check the ruleset ordering in CoPilot.

**2. `prod_cluster_id` / `nonprod_cluster_id` not known**

These values are only available after the Controller has inventoried each cluster. After deploying Layers 2 and 3, wait 2–3 minutes, then go to CoPilot → Security → DCF → SmartGroups. Create a new K8s SmartGroup — the Controller will list all discovered cluster IDs in the dropdown. Copy these IDs into `aws/network/terraform.tfvars` and re-run `terraform apply` in `aws/network/`.

**3. Database VPC unreachable from prod**

Check that `aviatrix_spoke_transit_attachment.db` exists in `aws/network/terraform.tfstate`. If the DB spoke attachment was not created, the DB spoke has no route via transit. Also confirm the DCF rule at priority 20 (`prod-to-db`) targets the correct SmartGroup UUIDs — these are stored in network outputs `sg_prod_vpc_uuid` and `sg_prod_db_uuid`.

**4. EIP quota exceeded during deploy**

Request an EIP quota increase to at least 20 before running `terraform apply`. If you have already started, run `terraform destroy` cleanly, request the quota increase, and retry. Alternatively, set `enable_ha = false` in `aws/network/terraform.tfvars` to halve EIP usage at the cost of gateway redundancy.

**5. Sandbox egress blocked**

The sandbox namespace uses the `sandbox_relaxed_egress` WebGroup (SNI filter `*`). If sandbox pods cannot reach HTTPS destinations, verify the `aviatrix_web_group.sandbox_relaxed_egress` resource exists in the network state and that the DCF rule at priority 51 references it. Re-apply `aws/network/` if the WebGroup is missing.

**6. FirewallPolicy CRDs not taking effect**

The Aviatrix k8s-firewall Helm chart must be running in each cluster (deployed by the nodes layer). Check: `kubectl get pods -n aviatrix-system --context pc2-prod`. If the pod is not running, re-apply `aws/nodes/prod`. Verify the Controller IP configured in the Helm release matches your `AVIATRIX_CONTROLLER_IP`.

**7. Autoscaling schedule not taking effect for nonprod**

The nonprod node group includes scale-down schedules for off-hours. Schedules use UTC time. Verify: `aws autoscaling describe-scheduled-actions --auto-scaling-group-name <asg-name> --region us-east-2`. Adjust the schedule times if your team is in a different timezone.

---

## Tested With

| Component | Version |
|---|---|
| Aviatrix Controller | 8.x |
| Aviatrix Terraform Provider | ~> 8.2.0 |
| Terraform | >= 1.5.0 |
| AWS Provider | ~> 5.0 |
| Kubernetes Provider | ~> 2.20 |
| Helm Provider | ~> 2.x |
| EKS Kubernetes Version | 1.35 |
| AWS CLI | v2 |
| kubectl | v1.35.x |
