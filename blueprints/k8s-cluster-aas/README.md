# k8s-cluster-aas — Cluster-as-a-Service

Each team gets a **dedicated EKS cluster in its own VPC**. Workload isolation is enforced by the **Aviatrix Cloud Native Security Fabric** — Distributed Cloud Firewall (DCF) at the VPC boundary — so no team can reach another team's cluster without an explicit PERMIT rule.

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
