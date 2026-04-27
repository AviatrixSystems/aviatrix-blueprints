# k8s-cluster-aas — Cluster-as-a-Service

Each team gets a **dedicated EKS cluster in its own VPC**. Network isolation is enforced by Aviatrix DCF at the VPC boundary — no team can reach another team's cluster without an explicit PERMIT rule.

## Architecture

```
Transit GW (10.2.0.0/20)
├── Team-A Spoke (10.10.0.0/20) ──── EKS cluster-a  [pods: 100.64.0.0/18]
├── Team-B Spoke (10.11.0.0/20) ──── EKS cluster-b  [pods: 100.64.64.0/18]
├── Team-C Spoke (10.12.0.0/20) ──── EKS cluster-c  [pods: 100.64.128.0/18]
└── DB Spoke     (10.5.0.0/22)  ──── Shared database
```

**VPCs:** 5 (transit + 3 team + DB) · **Clusters:** 3 · **Kubernetes:** 1.35

### Pod Networking
Pods use RFC 6598 overlay CIDR (`100.64.0.0/16`). Aviatrix SNAT translates pod IPs to the spoke gateway IP before traffic hits DCF. **DCF sees POST-SNAT traffic** — use VPC SmartGroups for source, hostname SmartGroups for destination.

### DCF Policy Layout

| Priority | Action | Rule |
|---|---|---|
| 100–101 | DENY | Geo-block (IR, KP, RU) + ThreatIQ feeds |
| 110 | PERMIT | team-a → team-b on TCP/443 |
| 111 | PERMIT | team-b → team-a on TCP/8080 |
| 120–123 | DENY | team-a ↔ team-c, team-b ↔ team-c (both directions) |
| 150 | PERMIT | All clusters → EKS required services (ECR, S3, STS, EKS API…) |
| 200 | DENY | Default deny public internet (non-RFC1918) |

## Resources Created

### AWS (per 3-team deployment)

| Resource | Count | Description |
|---|---|---|
| `aviatrix_transit_gateway` | 1 | Transit hub (c5.xlarge) connecting all spokes |
| `aviatrix_vpc` | 4 | One VPC per team + database VPC |
| `aviatrix_spoke_gateway` | 3–6 | One per team VPC (doubles with HA enabled) |
| `aviatrix_spoke_transit_attachment` | 4 | Connects each spoke to transit |
| `aviatrix_gateway_snat` | 3 | Masquerades pod CIDR (100.64.0.0/16) to spoke gateway IP |
| `aviatrix_distributed_firewalling_config` | 1 | Enables DCF on the transit |
| `aviatrix_k8s_config` | 1 | Enables Kubernetes enforcement in DCF |
| `aviatrix_kubernetes_cluster` | 3 | Registers each EKS cluster with the Controller |
| `aviatrix_smart_group` | 6 | 3× team VPC + database + geo-block + ThreatIQ |
| `aviatrix_web_group` | 1 | Approved cloud service egress domains |
| `aviatrix_dcf_ruleset` | 1 | Priority-ordered DCF policy (inter-team + egress) |
| `aws_vpc` (via module) | 4 | Transit + 3 team + database (subnets, IGW, route tables included) |
| `aws_nat_gateway` | ~12 | ~3 per VPC (one per AZ) — verify EIP quota |
| `aws_eks_cluster` | 3 | One dedicated EKS cluster per team |
| `aws_eks_node_group` | 3 | Managed node group per cluster |
| `aws_eks_addon` | 9 | vpc-cni, coredns, kube-proxy per cluster |
| `aws_iam_openid_connect_provider` | 3 | IRSA OIDC provider per cluster |
| `aws_iam_role` (IRSA) | 6+ | ALB Controller + ExternalDNS roles per cluster |
| `aws_route53_zone` | 1 | Private hosted zone for internal DNS |
| `helm_release` | 6 | ALB Controller + ExternalDNS per cluster |
| `kubernetes_config_map` | 3+ | ENIConfig per AZ for VPC CNI custom networking |

> Azure and GCP deployments create equivalent resources using AKS/GKE, Azure Private DNS / Cloud DNS, and NGINX Ingress / Gateway API respectively.

## Deployment

```
Layer 1: aws/network/            ← Transit, VPCs, Spokes, DNS, DCF  (~8 min)
Layer 2: aws/clusters/team-*/    ← EKS control planes (parallel)    (~15 min)
Layer 3: aws/nodes/team-*/       ← Node groups, Helm charts (parallel) (~8 min)
```

### Prerequisites
- Aviatrix Controller with AWS account onboarded
- AWS credentials with sufficient permissions
- Terraform ≥ 1.5, Aviatrix provider ~> 8.2

### Layer 1 — Network

```bash
cd aws/network
terraform init
terraform apply -var="aviatrix_aws_account_name=<account>"
```

| Variable | Default | Description |
|---|---|---|
| `aviatrix_aws_account_name` | required | Aviatrix access account name |
| `aws_region` | `us-west-2` | AWS region |
| `name_prefix` | `caas` | Resource name prefix |
| `random_suffix` | `true` | Append random hex (e.g. `caas-4462`) |
| `pod_cidr` | `100.64.0.0/16` | Pod overlay CIDR |
| `private_dns_zone_name` | `aws.aviatrixdemo.local` | Route53 private zone |

### Layer 2 — Clusters (parallel)

```bash
for team in team-a team-b team-c; do
  terraform -chdir=aws/clusters/$team init
  terraform -chdir=aws/clusters/$team apply \
    -var="aviatrix_aws_account_name=<account>" -auto-approve &
done && wait
```

| Variable | Default | Description |
|---|---|---|
| `kubernetes_version` | `1.35` | EKS version |
| `enable_network_policy` | `true` | Calico (policy-only mode) |

### Layer 3 — Nodes (parallel)

```bash
for team in team-a team-b team-c; do
  terraform -chdir=aws/nodes/$team init
  terraform -chdir=aws/nodes/$team apply -auto-approve &
done && wait
```

| Variable | Default | Description |
|---|---|---|
| `node_group_config.instance_type` | `t3.large` | EC2 instance type |
| `node_group_config.desired_size` | `2` | Node count |
| `node_group_config.capacity_type` | `SPOT` | `SPOT` or `ON_DEMAND` |

## Variables Reference

### Network (`aws/network/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `aviatrix_aws_account_name` | string | — | yes | AWS account name as registered in Aviatrix Controller |
| `aws_region` | string | `us-west-2` | no | AWS region for all resources |
| `name_prefix` | string | `caas` | no | Prefix for all resource names |
| `transit_cidr` | string | `10.2.0.0/20` | no | CIDR for the Aviatrix transit VPC |
| `team_a_vpc_cidr` | string | `10.10.0.0/20` | no | Primary CIDR for team-a EKS VPC |
| `team_b_vpc_cidr` | string | `10.11.0.0/20` | no | Primary CIDR for team-b EKS VPC |
| `team_c_vpc_cidr` | string | `10.12.0.0/20` | no | Primary CIDR for team-c EKS VPC |
| `db_vpc_cidr` | string | `10.5.0.0/22` | no | CIDR for the database spoke VPC |
| `pod_cidr` | string | `100.64.0.0/16` | no | Overlay CIDR for pod networking (RFC6598) |
| `private_dns_zone_name` | string | `aws.aviatrixdemo.local` | no | Route53 private hosted zone domain name |
| `db_private_ip` | string | `10.5.0.10` | no | Private IP address of the database |
| `random_suffix` | bool | `true` | no | Append a random suffix to all resource names |
| `manage_dcf` | bool | `true` | no | Whether this blueprint manages DCF lifecycle |

### Cluster (`aws/clusters/team-*/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `aviatrix_aws_account_name` | string | — | yes | Aviatrix access account name for AWS |
| `kubernetes_version` | string | `1.35` | no | Kubernetes version for the EKS cluster |
| `enable_private_endpoint` | bool | `false` | no | Disable public access to the EKS API server endpoint |
| `enable_control_plane_logging` | bool | `false` | no | Enable EKS control plane logging |

### Nodes (`aws/nodes/team-*/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `node_group_config` | object | see below | no | Configuration for EKS managed node groups |
| `node_group_config.min_size` | number | `1` | no | Minimum node count |
| `node_group_config.max_size` | number | `3` | no | Maximum node count |
| `node_group_config.desired_size` | number | `2` | no | Desired node count |
| `node_group_config.instance_type` | string | `t3.large` | no | EC2 instance type |
| `node_group_config.capacity_type` | string | `SPOT` | no | `SPOT` or `ON_DEMAND` |
| `alb_controller_chart_version` | string | `1.8.0` | no | Helm chart version for AWS ALB Controller |
| `external_dns_chart_version` | string | `1.15.0` | no | Helm chart version for ExternalDNS |

## Outputs Reference

### Network (`aws/network/`)

| Output | Description |
|---|---|
| `transit_gateway_name` | Aviatrix transit gateway name |
| `transit_vpc_id` | Transit VPC ID |
| `team_a_vpc_id` | Team-A VPC ID |
| `team_a_private_subnet_ids` | Team-A private subnet IDs for EKS node groups |
| `team_a_pod_subnet_ids` | Team-A pod subnet IDs for VPC CNI custom networking |
| `team_a_spoke_gateway_name` | Team-A spoke gateway name |
| `team_b_vpc_id` | Team-B VPC ID |
| `team_b_private_subnet_ids` | Team-B private subnet IDs for EKS node groups |
| `team_b_pod_subnet_ids` | Team-B pod subnet IDs for VPC CNI custom networking |
| `team_b_spoke_gateway_name` | Team-B spoke gateway name |
| `team_c_vpc_id` | Team-C VPC ID |
| `team_c_private_subnet_ids` | Team-C private subnet IDs for EKS node groups |
| `team_c_pod_subnet_ids` | Team-C pod subnet IDs for VPC CNI custom networking |
| `team_c_spoke_gateway_name` | Team-C spoke gateway name |
| `route53_zone_id` | Route53 private hosted zone ID |
| `private_dns_zone_name` | Route53 private hosted zone domain name |
| `team_a_cluster_name` | Team-A EKS cluster name |
| `team_b_cluster_name` | Team-B EKS cluster name |
| `team_c_cluster_name` | Team-C EKS cluster name |
| `aws_region` | AWS region |

### Cluster (`aws/clusters/team-*/`)

| Output | Description |
|---|---|
| `cluster_name` | EKS cluster name |
| `cluster_arn` | EKS cluster ARN |
| `cluster_endpoint` | EKS cluster API endpoint |
| `cluster_certificate_authority_data` | Base64 encoded CA certificate (sensitive) |
| `oidc_provider_arn` | OIDC provider ARN for IRSA |
| `alb_controller_role_arn` | IAM role ARN for ALB Controller |
| `external_dns_role_arn` | IAM role ARN for ExternalDNS |

### Nodes (`aws/nodes/team-*/`)

Nodes workspaces expose no outputs — node groups are consumed by Kubernetes directly.

## Traffic Tests

```bash
# Configure kubectl contexts
aws eks update-kubeconfig --name <cluster-name> --alias team-a --region us-west-2

# Deploy test containers
for team in team-a team-b team-c; do
  kubectl apply -f aws/k8s-apps/traffic-test/$team/
done

# Run automated tests
cd aws/k8s-apps/traffic-test && ./run-tests.sh team-a team-b team-c
```

Expected: **8/8 pass**

| Test | Expected | DCF Rule |
|---|---|---|
| team-a → team-b:443 | PASS | PERMIT 110 |
| team-b → team-a:8080 | PASS | PERMIT 111 |
| team-a ↔ team-c | BLOCKED | DENY 120/121 |
| team-b ↔ team-c | BLOCKED | DENY 122/123 |
| egress registry.k8s.io | PASS | PERMIT 150 |
| egress example.com | BLOCKED | DEFAULT DENY 200 |

## Troubleshooting

**EIP quota exceeded during apply**

This blueprint creates ~12 NAT Gateways plus up to 6 Aviatrix gateway EIPs per region. AWS default EIP quota is 5. Request an increase to at least 20 before deploying. Check: AWS Console → Service Quotas → EC2 → Elastic IP addresses.

**`aviatrix_kubernetes_cluster` fails: cluster not found**

The nodes layer must be applied after the EKS cluster is Ready and the Aviatrix Controller has completed its K8s inventory sync (typically 2–5 min). If this fails, wait and re-run `terraform apply` in `nodes/team-X/`.

**Pods can't reach external services**

Verify the SNAT rules are applied: in the Aviatrix Controller, check Gateways → [spoke gateway] → SNAT. The pod CIDR `100.64.0.0/16` must be translated to the spoke gateway's private IP. If SNAT rules are missing, re-apply the network layer.

**DCF rules not enforcing**

If traffic is passing when it should be blocked, check that `aviatrix_distributed_firewalling_config` was applied and DCF is enabled in CoPilot → Security → Distributed Cloud Firewall.

**ENIConfig not found for AZ**

If new pods are stuck Pending with "no ENIConfig found for AZ", verify `kubernetes_config_map` resources were applied in the nodes layer. Check: `kubectl get eniconfig -A`.

**Terraform state conflict between layers**

Each layer uses local state. If a layer was partially applied, run `terraform state list` to see what was created, then `terraform apply` again. Never run `terraform destroy` on `network/` before destroying `clusters/` and `nodes/` first.

## Destroy (reverse order)

```bash
for team in team-a team-b team-c; do terraform -chdir=aws/nodes/$team destroy -auto-approve & done && wait
for team in team-a team-b team-c; do terraform -chdir=aws/clusters/$team destroy -var="aviatrix_aws_account_name=<account>" -auto-approve & done && wait
terraform -chdir=aws/network destroy -var="aviatrix_aws_account_name=<account>" -auto-approve
```

## Key Design Notes

- **excluded_advertised_spoke_routes goes on the TRANSIT**, not spokes — software-defined routing, not BGP
- **Always deny BOTH directions** between isolated teams — asymmetric rules cause traffic asymmetry issues
- **Do NOT use `0.0.0.0/0` for default deny** — blocks RFC1918 east-west traffic. Use the built-in Public Internet SmartGroup instead
- **Calico in policy-only mode** — VPC CNI handles pod networking; Calico adds Kubernetes NetworkPolicy enforcement

## When to Use

Choose this pattern when teams need **full cluster autonomy**, different Kubernetes versions, or strict compliance isolation. For a cost-effective shared alternative, see [k8s-namespace-aas](../k8s-namespace-aas/). For the recommended balanced approach, see [k8s-prod-nonprod-hybrid](../k8s-prod-nonprod-hybrid/).
