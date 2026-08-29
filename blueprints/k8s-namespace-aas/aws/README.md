# Namespace-as-a-Service — AWS (EKS)

All teams share a **single EKS cluster** with namespace-level workload isolation enforced by the **Aviatrix Cloud Native Security Fabric (CNSF)** — Distributed Cloud Firewall (DCF) at the transit layer paired with Calico NetworkPolicy intra-cluster. Kubernetes RBAC prevents accidental cross-namespace access but is not a security boundary; DCF and NetworkPolicy are the enforcement mechanisms.

---

## Architecture Diagram

<!-- TODO: Add architecture diagram — place architecture.png or architecture.svg in this directory -->

```
Transit VPC (10.2.0.0/20)
  Aviatrix Transit GW
      │
      └── Shared Spoke VPC (10.10.0.0/16)
              Aviatrix Spoke GW (SNAT: 100.64.0.0/16 → spoke-ip)
                  │
                  └── EKS Shared Cluster
                          ├── namespace: team-a  [pods: 100.64.x.x]
                          ├── namespace: team-b  [pods: 100.64.x.x]
                          └── namespace: team-c  [pods: 100.64.x.x]
```

Pod traffic is SNATed from the RFC 6598 overlay CIDR (`100.64.0.0/16`) to the spoke gateway IP before entering the transit. DCF SmartGroups match on the originating Kubernetes namespace; Calico NetworkPolicy provides a second enforcement layer for intra-cluster pod-to-pod traffic.

### DCF Policy Layout

| Priority | Action | Rule |
|---|---|---|
| 0 | DENY | Geo-block inbound (CN, RU, KP, IR) |
| 1 | DENY | ThreatIQ (major + critical severity) |
| 5 | PERMIT | monitoring namespace → all team namespaces on TCP/9090-9091 |
| 10 | PERMIT | team-a → team-b on TCP/443 |
| 50 | DENY | team-a → team-c |
| 51 | DENY | team-c → team-a |
| 52 | DENY | team-b → team-c |
| 55 | DENY | team-c → team-b |
| 60 | PERMIT | All namespaces → public internet (EKS required + approved domains, TCP/443) |
| 70–99 | (reserved) | CRD-managed team self-service rules (GitOps) |

---

## Prerequisites

### Aviatrix Controller

| Requirement | Details |
|---|---|
| Aviatrix Controller | Version compatible with provider ~> 8.2; must be running and accessible |
| Aviatrix CoPilot | Recommended for DCF visualization and SmartGroups UI |
| AWS Account Onboarded | Account name registered in the Controller (used for `aviatrix_aws_account_name`) |
| DCF Enabled | Either pre-enabled by your Controller admin OR set `manage_dcf = true` if this blueprint owns DCF lifecycle |

### Local Tools

| Tool | Min Version | Notes |
|---|---|---|
| Terraform | >= 1.5 | [Install](https://developer.hashicorp.com/terraform/install) |
| AWS CLI | v2 | [Install](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) — used for EKS kubectl auth |
| kubectl | Latest | [Install](https://kubernetes.io/docs/tasks/tools/) |
| helm | Latest | [Install](https://helm.sh/docs/intro/install/) |

### AWS IAM Permissions

The credentials used must have permissions to create:
- EKS: clusters, managed node groups, add-ons, OIDC providers
- VPC: VPCs, subnets, route tables, internet/NAT gateways, security groups
- IAM: roles and policies (IRSA for node groups and Helm add-ons)
- Route53: private hosted zones and record sets
- ELB: Application Load Balancers
- EC2: instances, ENIs

> `AdministratorAccess` covers all required permissions for demo environments. For production, scope it down.

### Environment Variables

```bash
# Aviatrix Controller
export AVIATRIX_CONTROLLER_IP="your-controller-ip"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="your-password"

# AWS credentials (choose one method)
# Option 1: env vars
export AWS_ACCESS_KEY_ID="your-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"

# Option 2: named profile
aws configure --profile demo
export AWS_PROFILE="demo"
```

---

## Resources Created

| Resource | Qty | Estimated hourly cost |
|---|---|---|
| `aviatrix_transit_gateway` | 1 | ~$0.17/hr (c5.xlarge) |
| `aviatrix_vpc` (transit) | 1 | — |
| `aviatrix_spoke_gateway` (shared, no HA) | 1 | ~$0.04/hr (t3.medium) |
| `aviatrix_spoke_transit_attachment` | 1 | — |
| `aviatrix_gateway_snat` | 1 | — |
| `aviatrix_distributed_firewalling_config` | 0 or 1 | — (only if manage_dcf=true) |
| `aviatrix_k8s_config` | 0 or 1 | — (only if manage_dcf=true) |
| `aviatrix_kubernetes_cluster` | 1 | — |
| `aviatrix_smart_group` | 7 | — |
| `aviatrix_web_group` | 2 | — |
| `aviatrix_dcf_ruleset` | 1 | — |
| `aws_vpc` (shared, via module) | 1 | — |
| `aws_nat_gateway` | ~2–3 | ~$0.045/hr each |
| `aws_eks_cluster` | 1 | $0.10/hr |
| `aws_eks_node_group` (3× m5.xlarge SPOT) | 1 | ~$0.06/hr (SPOT estimate) |
| `aws_eks_addon` (vpc-cni, coredns, kube-proxy) | 3 | — |
| `aws_iam_openid_connect_provider` | 1 | — |
| `aws_iam_role` (ALB controller + ExternalDNS) | 2 | — |
| `aws_route53_zone` (private) | 1 | $0.50/mo |
| `helm_release` (ALB controller, ExternalDNS) | 2 | — |
| `kubernetes_config_map` (ENIConfig per AZ) | ~2 | — |

> Estimated cost at defaults (us-east-1, 3 SPOT nodes, no HA): roughly **$0.45–0.55/hr** (~$330–400/month). Aviatrix licensing is billed separately.

---

## Deployment Instructions

### Step 0 — Set environment variables

```bash
export AVIATRIX_CONTROLLER_IP="your-controller-ip"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="your-password"

# Verify AWS credentials
aws sts get-caller-identity
```

### Step 1 — Layer 1: Network (~10 min)

```bash
cd aws/network

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   aviatrix_aws_account_name = "your-account-name"
#   aws_region                = "us-east-1"
#   # Leave k8s_cluster_id empty for now — fill in after Step 2

terraform init
terraform apply -var-file=terraform.tfvars
```

### Step 2 — Layer 2: Shared EKS Cluster (~15 min)

```bash
cd aws/clusters/shared

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   aviatrix_aws_account_name = "your-account-name"

terraform init
terraform apply -var-file=terraform.tfvars

# Note the cluster_arn output — needed for DCF SmartGroups
terraform output cluster_arn
```

### Step 2b — Update network layer with cluster ARN (SmartGroups)

```bash
cd aws/network

# Edit terraform.tfvars:
#   k8s_cluster_id = "<cluster_arn from Step 2>"

terraform apply -var-file=terraform.tfvars
```

### Step 3 — Layer 3: Node Group + Helm Add-ons (~8 min)

```bash
cd aws/nodes/shared

terraform init
terraform apply
# No tfvars required if using defaults; create one from the example if customizing
```

### Step 4 — Layer 4: Kubernetes Apps (< 1 min)

```bash
# Configure kubectl
cd aws/clusters/shared
$(terraform output -raw kubectl_config_command)

# Apply namespace isolation CRDs and network policies
kubectl apply -f aws/k8s-apps/dcf-crd/
```

---

## Variables Reference

### Layer 1 — aws/network

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `name_prefix` | string | `"naas"` | No | Prefix for all resource names |
| `aviatrix_aws_account_name` | string | — | **Yes** | AWS account name registered in the Aviatrix Controller |
| `aws_region` | string | `"us-east-1"` | No | AWS region |
| `env` | string | `"prod"` | No | Environment tag value |
| `transit_cidr` | string | `"10.2.0.0/20"` | No | CIDR for the Aviatrix transit VPC |
| `shared_vpc_cidr` | string | `"10.10.0.0/16"` | No | CIDR for the shared cluster VPC |
| `pod_cidr` | string | `"100.64.0.0/16"` | No | Secondary CIDR for pod networking (RFC 6598) |
| `private_dns_zone_name` | string | `"aws-naas.aviatrixdemo.local"` | No | Route53 private hosted zone domain |
| `k8s_cluster_suffix` | string | `"shared-eks"` | No | Suffix appended to `name_prefix` for the cluster name |
| `k8s_cluster_id` | string | `""` | No | EKS cluster ARN for DCF SmartGroups (fill in after clusters/shared/ apply) |
| `team_namespaces` | list(string) | `["team-a","team-b","team-c"]` | No | Team namespace names (used for SmartGroup naming only — DCF rules are hardcoded) |
| `geo_block_countries` | list(string) | `["CN","RU","KP","IR"]` | No | ISO country codes to geo-block |
| `approved_web_domains` | list(string) | `["*.amazonaws.com","docker.io",…]` | No | Domains permitted for namespace egress |
| `random_suffix` | bool | `true` | No | Append random hex to resource names |
| `manage_dcf` | bool | `false` | No | Set `true` only if this blueprint owns DCF lifecycle on the controller |
| `controller_ip` | string | null | No | Override Aviatrix Controller IP (prefer AVIATRIX_CONTROLLER_IP env var) |
| `controller_username` | string | `"admin"` | No | Override Aviatrix username |
| `controller_password` | string | null | No | Override Aviatrix password (sensitive; prefer env var) |

### Layer 2 — aws/clusters/shared

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `aviatrix_aws_account_name` | string | — | **Yes** | Aviatrix access account name for AWS |
| `kubernetes_version` | string | `"1.35"` | No | EKS Kubernetes version |
| `cluster_endpoint_public_access` | bool | `true` | No | Enable public EKS API endpoint |
| `enable_private_endpoint` | bool | `false` | No | Private-only API endpoint (requires bastion or VPN) |
| `enable_control_plane_logging` | bool | `false` | No | Enable EKS control plane logging to CloudWatch |

### Layer 3 — aws/nodes/shared

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `node_group_config` | object | `{min=2, max=6, desired=3, type="m5.xlarge", SPOT}` | No | EKS managed node group configuration |
| `alb_controller_chart_version` | string | `"1.8.0"` | No | Helm chart version for AWS Load Balancer Controller |
| `external_dns_chart_version` | string | `"1.15.0"` | No | Helm chart version for ExternalDNS |

---

## Outputs Reference

### aws/network outputs

| Output | Description |
|---|---|
| `transit_gateway_name` | Aviatrix transit gateway name |
| `shared_vpc_id` | Shared cluster VPC ID |
| `shared_vpc_cidr` | Shared cluster VPC primary CIDR |
| `shared_private_subnets` | Private subnet IDs (EKS nodes) |
| `shared_public_subnets` | Public subnet IDs |
| `shared_pod_subnet_ids` | Pod subnet IDs from the secondary CIDR |
| `shared_pod_subnet_azs` | Pod subnet availability zones |
| `shared_spoke_gateway_name` | Shared spoke gateway name |
| `shared_spoke_gateway_private_ip` | Spoke gateway private IP (SNAT target) |
| `private_dns_zone_id` | Route53 private hosted zone ID |
| `private_dns_zone_name` | Route53 private hosted zone domain |
| `shared_cluster_name` | EKS cluster name |
| `aws_region` | AWS region |
| `pod_cidr` | Pod overlay CIDR |
| `name_prefix` | Name prefix used for all resources |

### aws/clusters/shared outputs

| Output | Description |
|---|---|
| `cluster_id` | EKS cluster ID |
| `cluster_name` | EKS cluster name |
| `cluster_version` | Kubernetes version |
| `cluster_endpoint` | EKS API server endpoint |
| `cluster_certificate_authority_data` | Base64 cluster CA cert |
| `cluster_security_group_id` | Cluster security group ID |
| `node_security_group_id` | Node security group ID |
| `oidc_provider_arn` | OIDC provider ARN for IRSA |
| `oidc_provider` | OIDC provider URL (without https://) |
| `kubectl_config_command` | `aws eks update-kubeconfig` command |
| `cluster_arn` | EKS cluster ARN (input for `k8s_cluster_id` in network layer) |

aws/nodes/shared exposes no outputs.

---

## Test Scenarios

### Scenario 1: Baseline namespace isolation

```bash
# Configure kubectl
cd aws/clusters/shared
$(terraform output -raw kubectl_config_command)

# Deploy test pods in each namespace
for ns in team-a team-b team-c; do
  kubectl -n $ns run nginx --image=nginx:alpine --port=80 --restart=Never
  kubectl -n $ns run netshoot --image=nicolaka/netshoot --command -- sleep infinity --restart=Never
  kubectl -n $ns expose pod nginx --port=443 --target-port=80 --name="${ns}-svc"
done

# Wait for pods
kubectl get pods -A -l run=nginx

# Test: team-a -> team-b (PERMIT — DCF rule 10 allows TCP/443)
kubectl -n team-a exec netshoot -- curl -sk --max-time 5 https://team-b-svc.team-b.svc.cluster.local
# Expected: nginx response (200) or TLS error — connection reaches the pod

# Test: team-a -> team-c (DENY — DCF rule 50)
kubectl -n team-a exec netshoot -- curl -sk --max-time 5 https://team-c-svc.team-c.svc.cluster.local
# Expected: connection timeout or reset

# Test: team-c -> team-b (DENY — DCF rule 55)
kubectl -n team-c exec netshoot -- curl -sk --max-time 5 https://team-b-svc.team-b.svc.cluster.local
# Expected: connection timeout or reset
```

Expected results:

| Test | Expected | Enforced by |
|---|---|---|
| team-a → team-b TCP/443 | PASS | DCF rule 10 |
| team-a → team-c | BLOCKED | Calico + DCF rule 50 |
| team-c → team-a | BLOCKED | Calico + DCF rule 51 |
| team-b → team-c | BLOCKED | Calico + DCF rule 52 |
| team-c → team-b | BLOCKED | Calico + DCF rule 55 |

### Scenario 2: Monitoring namespace scrape access

```bash
kubectl create namespace monitoring

kubectl -n monitoring run netshoot --image=nicolaka/netshoot --command -- sleep infinity --restart=Never

# Test: monitoring -> team-a on TCP/9090 (PERMIT — DCF rule 5)
kubectl -n monitoring exec netshoot -- curl -sk --max-time 5 http://nginx.team-a.svc.cluster.local:9090
# Expected: connection attempt reaches the pod (may 404 — that is a pass; timeout is a fail)

# Test: monitoring -> team-a on TCP/80 (no PERMIT rule — expect DENY)
kubectl -n monitoring exec netshoot -- curl -sk --max-time 5 http://nginx.team-a.svc.cluster.local:80
# Expected: connection timeout
```

### Scenario 3: Egress to approved domains

```bash
# Test: team-a egress to an approved domain (PERMIT — DCF rule 60)
kubectl -n team-a exec netshoot -- curl -s --max-time 10 https://ghcr.io/v2/
# Expected: HTTP 200 or 401 (reached the server)

# Test: team-a egress to an unapproved domain (DENY — no matching rule)
kubectl -n team-a exec netshoot -- curl -s --max-time 10 https://example.com
# Expected: connection timeout or TLS error
```

---

## Cleanup / Destroy

Destroy in reverse layer order.

```bash
# Step 1: Remove Kubernetes resources (clean up LoadBalancers and trigger ExternalDNS cleanup)
kubectl delete -f aws/k8s-apps/dcf-crd/
kubectl delete svc -A --field-selector spec.type=LoadBalancer
kubectl delete ingress --all -A
# Wait ~60 seconds for AWS to de-register LBs before destroying nodes

# Step 2: Destroy Layer 3 — nodes
terraform -chdir=aws/nodes/shared destroy -auto-approve

# Step 3: Destroy Layer 2 — cluster
terraform -chdir=aws/clusters/shared destroy \
  -var="aviatrix_aws_account_name=your-account-name" -auto-approve

# Step 4: Destroy Layer 1 — network
terraform -chdir=aws/network destroy -var-file=terraform.tfvars -auto-approve
```

**Manual cleanup steps:**

- If ExternalDNS-managed Route53 records (CNAME/TXT) are not removed before Step 2, they will be orphaned. Check with:
  ```bash
  cd aws/network
  aws route53 list-resource-record-sets \
    --hosted-zone-id $(terraform output -raw private_dns_zone_id) \
    --query "ResourceRecordSets[?Type=='CNAME' || Type=='TXT']"
  ```
- If `manage_dcf = true`, verify DCF is in the desired state after destroy. DCF and k8s_config are shared controller resources — destroying them affects all blueprints on the same controller.

**Verify cleanup:**

```bash
# Confirm no Aviatrix resources remain
terraform -chdir=aws/network state list   # should return empty or error
terraform -chdir=aws/clusters/shared state list
terraform -chdir=aws/nodes/shared state list

# Confirm no EKS clusters remain in your region
aws eks list-clusters --region us-east-1
```

---

## Troubleshooting

**Namespace SmartGroups not enforcing**

DCF namespace enforcement requires the Aviatrix Controller to have read access to the EKS cluster. Verify that the IAM role `aviatrix-eks-view-<suffix>` was created by the clusters/shared/ layer and that the Controller's IAM role trusts it. In CoPilot, go to Security → Distributed Cloud Firewall → SmartGroups and confirm your team namespaces appear as populated groups.

**`k8s_cluster_id` mismatch — pods match wrong or no SmartGroup**

The `k8s_cluster_id` in DCF SmartGroups must exactly match the cluster identifier as registered in the Controller. After deploying clusters/shared/, run `terraform output cluster_arn` in that directory and paste the value into the network layer's `k8s_cluster_id` variable. Re-apply the network layer.

**EIP quota exceeded during network apply**

Aviatrix gateway EIPs plus NAT gateway EIPs can hit the default quota of 5 EIPs per region. Request an increase via the AWS console (EC2 → Elastic IPs → Request limit increase) before deploying.

**Inter-namespace traffic not blocked (SNAT not working)**

DCF matches on post-SNAT source IPs. If SNAT is broken, pods present their original `100.64.x.x` IPs to the gateway, which will not match any SmartGroup. Verify:
```bash
# Pod IPs should be from the 100.64.0.0/16 range
kubectl get pods -A -o wide | grep 100.64

# Check the SNAT policy in the Aviatrix Controller
# Gateway → shared spoke → SNAT — should show 100.64.0.0/16 → spoke-ip
```

**Helm releases fail with "kubernetes provider not configured"**

The `helm` and `kubernetes` providers in nodes/shared/ read the EKS endpoint and CA cert from `clusters/shared/terraform.tfstate`. If the state file is missing, the plan fails. Ensure clusters/shared/ was applied successfully before running nodes/shared/.

**Calico pods stuck in `Init` or `CrashLoopBackOff`**

Calico pulls images from docker.io. Verify `docker.io` and `*.docker.io` are in the `approved_web_domains` list. The default value includes them; do not remove them.

**`terraform destroy` hangs on `aviatrix_kubernetes_cluster`**

The Controller deregisters the cluster asynchronously. If destroy hangs, check the Controller's K8s inventory to confirm the cluster was removed, then run `terraform state rm aviatrix_kubernetes_cluster.this` and re-run destroy.

---

## Tested With

| Component | Version |
|---|---|
| Aviatrix Controller | 7.2.x |
| Aviatrix Terraform Provider | ~> 8.2.0 |
| Terraform | >= 1.5 |
| AWS Provider | ~> 5.0 |
| Kubernetes Provider | ~> 2.20 |
| Helm Provider | ~> 2.x |
| EKS Kubernetes version | 1.35 |
| AWS Load Balancer Controller chart | 1.8.0 |
| ExternalDNS chart | 1.15.0 |
