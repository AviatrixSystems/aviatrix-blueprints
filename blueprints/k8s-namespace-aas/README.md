# k8s-namespace-aas — Namespace-as-a-Service

All teams share a **single EKS cluster** with namespace-level workload isolation enforced by the **Aviatrix Cloud Native Security Fabric** — Distributed Cloud Firewall (DCF) at the transit layer — paired with Calico NetworkPolicy intra-cluster. Kubernetes RBAC prevents accidental cross-namespace access but is **not a security boundary** — DCF and NetworkPolicy are the enforcement mechanisms.

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
