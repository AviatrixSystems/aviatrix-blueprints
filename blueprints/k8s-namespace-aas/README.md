# k8s-namespace-aas — Namespace-as-a-Service

All teams share a **single EKS cluster** with namespace-level isolation enforced by Aviatrix DCF (transit-level) and Calico NetworkPolicy (intra-cluster). Kubernetes RBAC prevents accidental cross-namespace access but is **not a network security boundary** — DCF and NetworkPolicy are the enforcement mechanisms.

## Architecture

```
Transit GW (10.2.0.0/20)
└── Shared Spoke (10.10.0.0/16) ──── EKS shared-cluster
                                          ├── namespace: team-a  [pods: 100.64.x.x]
                                          ├── namespace: team-b  [pods: 100.64.x.x]
                                          └── namespace: team-c  [pods: 100.64.x.x]
```

**VPCs:** 2 (transit + shared) · **Clusters:** 1 (shared) · **Kubernetes:** 1.35

### Pod Networking
Pods use RFC 6598 overlay CIDR (`100.64.0.0/16`). Aviatrix SNAT translates pod IPs to the spoke gateway IP for east-west and egress traffic. Intra-cluster east-west stays within the VPC fabric and is enforced by Calico NetworkPolicy.

### Two-Layer Isolation

| Layer | Mechanism | Scope |
|---|---|---|
| Cross-VPC | Aviatrix DCF at spoke gateway | Between clusters / external egress |
| Intra-cluster | Calico NetworkPolicy (iptables) | Between namespaces, same cluster |

### DCF Policy Layout

| Priority | Action | Rule |
|---|---|---|
| 0–1 | DENY | Geo-block (IR, KP, RU) + ThreatIQ |
| 5 | PERMIT | Monitoring namespace → all namespaces on TCP/9090 |
| 10 | PERMIT | team-a → team-b on TCP/443 |
| 50–55 | DENY | Namespace isolation (team-a ↔ team-c, team-b ↔ team-c) |
| 60 | PERMIT | All namespaces → EKS required services egress |

### Calico NetworkPolicy (intra-cluster)
Deployed via `aws/k8s-apps/dcf-crd/network-policies.yaml`:
- **team-a**: allow same namespace, deny other namespaces
- **team-b**: allow same namespace + team-a ingress (mirrors DCF rule 10)
- **team-c**: allow same namespace only (fully isolated)

## Deployment

```
Layer 1: aws/network/          ← Transit, VPC, Spoke, DNS, DCF  (~8 min)
Layer 2: aws/clusters/shared/  ← Shared EKS control plane        (~15 min)
Layer 3: aws/nodes/shared/     ← Node group, ENIConfig, Helm      (~8 min)
Layer 4: aws/k8s-apps/         ← Namespaces, RBAC, NetworkPolicy  (<1 min)
```

### Prerequisites
- Aviatrix Controller with AWS account onboarded
- AWS credentials with sufficient permissions
- Terraform ≥ 1.5 · kubectl · helm

### Layer 1 — Network

```bash
cd aws/network
terraform init
terraform apply -var="aviatrix_aws_account_name=<account>"
```

| Variable | Default | Description |
|---|---|---|
| `aviatrix_aws_account_name` | required | Aviatrix access account name |
| `aws_region` | `us-east-1` | AWS region |
| `name_prefix` | `naas` | Resource name prefix |
| `random_suffix` | `true` | Append random hex (e.g. `naas-9d4c`) |
| `shared_vpc_cidr` | `10.10.0.0/16` | Shared cluster VPC CIDR |
| `pod_cidr` | `100.64.0.0/16` | Pod overlay CIDR |
| `k8s_cluster_suffix` | `shared-eks` | Suffix for cluster name |
| `team_namespaces` | `["team-a","team-b","team-c"]` | Teams to isolate |
| `approved_web_domains` | `[*.amazonaws.com, ghcr.io, docker.io…]` | Approved egress domains |

### Layer 2 — Cluster

```bash
cd aws/clusters/shared
terraform init
terraform apply -var="aviatrix_aws_account_name=<account>"
```

| Variable | Default | Description |
|---|---|---|
| `kubernetes_version` | `1.35` | EKS version |

### Layer 3 — Nodes

```bash
cd aws/nodes/shared
terraform init && terraform apply
```

| Variable | Default | Description |
|---|---|---|
| `node_group_config.instance_type` | `t3.large` | EC2 instance type |
| `node_group_config.desired_size` | `2` | Node count |
| `node_group_config.capacity_type` | `SPOT` | `SPOT` or `ON_DEMAND` |
| `enable_network_policy` | `true` | Calico (policy-only mode) |

### Layer 4 — K8s Apps

```bash
# Apply namespace isolation policies
kubectl apply -f aws/k8s-apps/dcf-crd/network-policies.yaml

# Optional: team self-service egress policies
kubectl apply -f aws/k8s-apps/dcf-crd/firewallpolicy-team-a.yaml
kubectl apply -f aws/k8s-apps/dcf-crd/firewallpolicy-team-b.yaml
```

## Traffic Tests

```bash
aws eks update-kubeconfig --name <cluster-name> --alias naas-shared --region us-east-1

# Create test pods per namespace
for ns in team-a team-b team-c; do
  kubectl -n $ns run nginx --image=nginx:alpine --port=80 --restart=Never
  kubectl -n $ns run netshoot --image=nicolaka/netshoot --command -- sleep infinity --restart=Never
  kubectl -n $ns expose pod nginx --port=443 --target-port=80 --name="${ns}-svc"
done
```

Expected results:

| Test | Expected | Enforced by |
|---|---|---|
| team-a → team-a (same ns) | PASS | — |
| team-a → team-b | PASS | Calico PERMIT + DCF rule 10 |
| team-a → team-c | BLOCKED | Calico DENY + DCF rule 50 |
| team-c → team-a | BLOCKED | Calico DENY + DCF rule 51 |
| team-b → team-c | BLOCKED | Calico DENY + DCF rule 52 |
| team-c → team-b | BLOCKED | Calico DENY + DCF rule 55 |

## Destroy (reverse order)

```bash
kubectl delete -f aws/k8s-apps/dcf-crd/
terraform -chdir=aws/nodes/shared destroy -auto-approve
terraform -chdir=aws/clusters/shared destroy -var="aviatrix_aws_account_name=<account>" -auto-approve
terraform -chdir=aws/network destroy -var="aviatrix_aws_account_name=<account>" -auto-approve
```

## Key Design Notes

- **RBAC is not a network boundary** — it prevents accidental access, DCF + NetworkPolicy enforce isolation
- **Two enforcement layers required for intra-cluster isolation** — DCF only sees traffic that traverses the spoke gateway; Calico covers pod-to-pod within the same VPC
- **`k8s_cluster_id` is required in K8s SmartGroups** — prevents cross-cluster namespace collisions when multiple clusters report to the same controller
- **Approved egress domains include docker.io** — Calico images pull from docker.io; add this to avoid image pull failures behind DCF

## When to Use

Choose this pattern when **cost and operational simplicity** matter more than blast-radius isolation. Best for trusted teams with controlled workloads. For stricter isolation, see [k8s-cluster-aas](../k8s-cluster-aas/). For the recommended balanced approach, see [k8s-prod-nonprod-hybrid](../k8s-prod-nonprod-hybrid/).

## Resources Created

| Resource | Count | Description |
|---|---|---|
| `aviatrix_transit_gateway` | 1 | Transit hub connecting the shared VPC spoke |
| `aviatrix_vpc` | 1 | Single shared VPC for all teams |
| `aviatrix_spoke_gateway` | 1–2 | Shared spoke gateway (+ HA if enabled) |
| `aviatrix_spoke_transit_attachment` | 1 | Connects shared VPC to transit |
| `aviatrix_gateway_snat` | 1 | Masquerades pod CIDR (100.64.0.0/16) to spoke gateway IP |
| `aviatrix_distributed_firewalling_config` | 1 | Enables DCF |
| `aviatrix_k8s_config` | 1 | Enables Kubernetes namespace enforcement in DCF |
| `aviatrix_kubernetes_cluster` | 1 | Registers the shared cluster with the Controller |
| `aviatrix_smart_group` | 7 | team-a, team-b, team-c, monitoring namespaces + all_namespaces aggregate + geo-block + ThreatIQ |
| `aviatrix_web_group` | 1 | Approved egress domains for all namespaces |
| `aviatrix_dcf_ruleset` | 1 | Namespace-level isolation policy |
| `aws_vpc` (via module) | 1 | Shared VPC (subnets, IGW, route tables included) |
| `aws_nat_gateway` | ~3 | One per AZ — verify EIP quota |
| `aws_eks_cluster` | 1 | Single shared EKS cluster |
| `aws_eks_node_group` | 1 | Shared managed node group |
| `aws_eks_addon` | 3 | vpc-cni, coredns, kube-proxy |
| `aws_iam_openid_connect_provider` | 1 | IRSA OIDC provider |
| `aws_iam_role` (IRSA) | 2 | ALB Controller + ExternalDNS (shared) |
| `aws_route53_zone` | 1 | Private hosted zone |
| `helm_release` | 2 | ALB Controller + ExternalDNS (one each, shared by all teams) |
| `kubernetes_config_map` | ~3 | ENIConfig per AZ for VPC CNI custom networking |

> This blueprint costs significantly less than `k8s-cluster-aas` for the same number of teams because all teams share one cluster, one VPC, and one set of controllers. The tradeoff is namespace-level (not VPC-level) isolation.

## Variables Reference

### Layer 1 — aws/network

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `name_prefix` | `string` | `"naas"` | No | Prefix for all resource names (enables multiple deployments in the same account) |
| `aviatrix_aws_account_name` | `string` | — | Yes | AWS account name as registered in Aviatrix Controller |
| `aws_region` | `string` | `"us-east-1"` | No | AWS region for all resources |
| `env` | `string` | `"prod"` | No | Environment name (e.g. prod, staging) |
| `transit_cidr` | `string` | `"10.2.0.0/20"` | No | CIDR for the Aviatrix transit VPC |
| `shared_vpc_cidr` | `string` | `"10.10.0.0/16"` | No | CIDR for the shared cluster VPC (all teams share this single VPC) |
| `pod_cidr` | `string` | `"100.64.0.0/16"` | No | Secondary CIDR for pod networking (VPC CNI custom networking, RFC6598) |
| `private_dns_zone_name` | `string` | `"aws-naas.aviatrixdemo.local"` | No | Route53 private hosted zone domain name |
| `k8s_cluster_suffix` | `string` | `"shared-eks"` | No | Suffix for the shared EKS cluster name (appended to name_prefix) |
| `team_namespaces` | `list(string)` | `["team-a","team-b","team-c"]` | No | List of team namespace names for SmartGroup creation |
| `geo_block_countries` | `list(string)` | `["CN","RU","KP","IR"]` | No | ISO country codes to geo-block |
| `approved_web_domains` | `list(string)` | `["*.amazonaws.com","registry.npmjs.org","pypi.org","ghcr.io","docker.io","*.docker.io","quay.io"]` | No | Domains permitted for namespace egress via WebGroups |
| `random_suffix` | `bool` | `true` | No | Append a random suffix to all resource names for uniqueness |
| `manage_dcf` | `bool` | `true` | No | Whether this blueprint manages DCF enable/disable lifecycle |

### Layer 2 — aws/clusters/shared

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `aviatrix_aws_account_name` | `string` | — | Yes | Aviatrix access account name for AWS (used to grant controller EKS access) |
| `kubernetes_version` | `string` | `"1.35"` | No | Kubernetes version for the shared EKS cluster |
| `cluster_endpoint_public_access` | `bool` | `true` | No | Whether to enable public access to the EKS API endpoint |
| `enable_private_endpoint` | `bool` | `false` | No | Disable public access to the EKS API server endpoint (private-only) |
| `enable_control_plane_logging` | `bool` | `false` | No | Enable EKS control plane logging (audit, api, authenticator, controllerManager, scheduler) |

### Layer 3 — aws/nodes/shared

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `node_group_config` | `object` | `{min_size=2, max_size=6, desired_size=3, instance_type="m5.xlarge", capacity_type="SPOT"}` | No | Configuration for EKS managed node group |
| `alb_controller_chart_version` | `string` | `"1.8.0"` | No | Helm chart version for AWS Load Balancer Controller |
| `external_dns_chart_version` | `string` | `"1.15.0"` | No | Helm chart version for ExternalDNS |

## Outputs Reference

| Output | Layer | Description |
|---|---|---|
| `transit_gateway_name` | network | Aviatrix transit gateway name |
| `shared_vpc_id` | network | Shared cluster VPC ID |
| `shared_vpc_cidr` | network | Shared cluster VPC primary CIDR |
| `shared_private_subnets` | network | Shared VPC private subnet IDs (for EKS nodes) |
| `shared_public_subnets` | network | Shared VPC public subnet IDs |
| `shared_pod_subnet_ids` | network | Pod subnet IDs in the secondary CIDR |
| `shared_pod_subnet_azs` | network | Pod subnet availability zones |
| `shared_spoke_gateway_name` | network | Shared spoke gateway name |
| `shared_spoke_gateway_private_ip` | network | Shared spoke gateway private IP (used for SNAT) |
| `private_dns_zone_id` | network | Route53 private hosted zone ID |
| `private_dns_zone_name` | network | Route53 private hosted zone domain name |
| `shared_cluster_name` | network | Shared EKS cluster name |
| `aws_region` | network | AWS region |
| `pod_cidr` | network | Overlay CIDR for pod networking |
| `name_prefix` | network | Name prefix used for all resources |
| `cluster_id` | clusters/shared | EKS cluster ID |
| `cluster_name` | clusters/shared | EKS cluster name |
| `cluster_version` | clusters/shared | Kubernetes version |
| `cluster_endpoint` | clusters/shared | EKS cluster API endpoint |
| `cluster_certificate_authority_data` | clusters/shared | Base64 encoded certificate data required to communicate with the cluster |
| `cluster_security_group_id` | clusters/shared | Security group ID attached to the EKS cluster |
| `node_security_group_id` | clusters/shared | Security group ID attached to the EKS nodes |
| `oidc_provider_arn` | clusters/shared | OIDC provider ARN for IRSA |
| `oidc_provider` | clusters/shared | OIDC provider URL (without https://) |
| `kubectl_config_command` | clusters/shared | aws CLI command to configure kubectl |
| `cluster_arn` | clusters/shared | EKS cluster ARN (used for Aviatrix kubernetes_cluster onboarding) |

nodes/shared exposes no outputs.

## Troubleshooting

**Namespace SmartGroups not enforcing**
DCF namespace enforcement requires the Aviatrix Controller to have read access to the EKS cluster. Verify that the IAM role `aviatrix-eks-view-<suffix>` was created (in `clusters/shared/`) and that the Controller's IAM role has `AmazonEKSViewPolicy`. Check CoPilot → Security → Distributed Cloud Firewall → SmartGroups to confirm namespaces appear.

**`k8s_cluster_id` mismatch**
The `k8s_cluster_id` in DCF SmartGroups must exactly match the cluster name as seen by the Aviatrix Controller (not necessarily the EKS cluster name). After deploying `nodes/shared/`, check the Controller's K8s inventory to get the correct ID, then re-apply `network/` if needed.

**EIP quota exceeded**
Even with one VPC, Aviatrix gateway EIPs + NAT gateway EIPs can hit the default quota of 5. Request an increase before deploying.

**Teams can reach each other's pods**
If inter-namespace traffic is not being blocked, check that `aviatrix_k8s_config` was applied and that pod IPs are being correctly SNATed. DCF sees post-SNAT traffic; if SNAT is broken, SmartGroup matching will fail.

**RBAC is not the isolation boundary**
A common mistake is relying on Kubernetes RBAC for team isolation. In this blueprint, RBAC is not enforced at the network level — DCF is the enforcement point. Do not assume K8s NetworkPolicy is active; it is not configured in this blueprint.

**Helm releases fail with provider configuration error**
The `helm` and `kubernetes` providers in `nodes/shared/` require the EKS cluster endpoint and CA certificate from the `clusters/shared/` state. Ensure `clusters/shared/terraform.tfstate` exists before applying `nodes/shared/`.
