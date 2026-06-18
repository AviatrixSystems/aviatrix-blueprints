# k8s-prod-nonprod-hybrid — Prod/Non-Prod Hybrid (Recommended)

Separate production and non-production EKS clusters secured by the **Aviatrix Cloud Native Security Fabric** with **two-layer DCF isolation**: environment-level (VPC SmartGroups) and namespace-level (K8s SmartGroups). Combines the strong workload isolation of cluster-aas with the team self-service of namespace-aas. HA enabled by default.

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

**VPCs:** 4 (transit + prod + nonprod + DB) · **Clusters:** 2 · **Kubernetes:** 1.35

### Two-Layer DCF Isolation

**Layer 1 — Environment boundary (VPC SmartGroups)**
- Prod VPC ↔ NonProd VPC: bidirectionally denied
- Database spoke: prod-only (transit routing + DCF rules)

**Layer 2 — Team namespace boundary (K8s SmartGroups)**
- Per-namespace SmartGroups (`k8s_namespace` + `k8s_cluster_id`)
- Teams define egress policies via FirewallPolicy CRDs (priority 70–99)

### DCF Policy Layout

| Priority | Action | Rule |
|---|---|---|
| 0–1 | DENY | Geo-block + ThreatIQ |
| 10 | DENY | prod-vpc → nonprod-vpc |
| 11 | DENY | nonprod-vpc → prod-vpc |
| 20–21 | DENY | monitoring-nonprod ↔ prod namespaces |
| 30 | DENY | nonprod → DB spoke |
| 31 | PERMIT | prod → DB spoke |
| 32 | PERMIT | monitoring-prod → prod namespaces (TCP/9090) |
| 50–51 | PERMIT | prod/nonprod egress → EKS required services |
| 70–99 | — | Team self-service via FirewallPolicy CRDs |

## Deployment

```
Layer 1: aws/network/              ← Transit(HA), VPCs, Spokes, DNS, DCF  (~8 min)
Layer 2: aws/clusters/prod|nonprod  ← EKS control planes (parallel)         (~15 min)
Layer 3: aws/nodes/prod|nonprod     ← Node groups, Helm charts (parallel)    (~8 min)
Layer 4: aws/k8s-apps/             ← Namespaces, RBAC, FirewallPolicy CRDs  (<1 min)
```

### Prerequisites
- Aviatrix Controller with AWS account onboarded
- AWS credentials with sufficient permissions
- Terraform ≥ 1.5 · kubectl · helm

### Layer 1 — Network

```bash
cd aws/network
terraform init
terraform apply -var="aws_account_name=<account>"
```

| Variable | Default | Description |
|---|---|---|
| `aws_account_name` | required | Aviatrix access account name |
| `aws_region` | `us-east-2` | AWS region |
| `environment_prefix` | `pc2` | Resource name prefix |
| `random_suffix` | `true` | Append random hex (e.g. `pc2-7160`) |
| `prod_vpc_cidr` | `10.10.0.0/20` | Production VPC CIDR |
| `nonprod_vpc_cidr` | `10.20.0.0/20` | Non-production VPC CIDR |
| `db_spoke_cidr` | `10.5.0.0/22` | Database spoke CIDR |
| `pod_cidr` | `100.64.0.0/16` | Pod overlay CIDR |
| `enable_ha` | `true` | Enable gateway HA |

### Layer 2 — Clusters (parallel)

```bash
terraform -chdir=aws/clusters/prod init
terraform -chdir=aws/clusters/prod apply -var="aviatrix_aws_account_name=<account>" -auto-approve &

terraform -chdir=aws/clusters/nonprod init
terraform -chdir=aws/clusters/nonprod apply -var="aviatrix_aws_account_name=<account>" -auto-approve &
wait
```

| Variable | Default | Description |
|---|---|---|
| `kubernetes_version` | `1.35` | EKS version |

### Layer 3 — Nodes (parallel)

```bash
terraform -chdir=aws/nodes/prod apply -auto-approve &
terraform -chdir=aws/nodes/nonprod apply -auto-approve &
wait
```

| Variable | Default | Description |
|---|---|---|
| `node_group_config.instance_type` | `t3.large` | EC2 instance type |
| `node_group_config.desired_size` | `2` | Node count |
| `enable_network_policy` | `true` | Calico (policy-only mode) |

### Layer 4 — K8s Apps (both clusters)

```bash
# Production cluster
aws eks update-kubeconfig --name <prod-cluster> --alias pc2-prod --region us-east-2
kubectl --context pc2-prod apply -f aws/k8s-apps/dcf-crd/prod-namespaces.yaml
kubectl --context pc2-prod apply -f aws/k8s-apps/dcf-crd/firewallpolicy-prod.yaml

# Non-production cluster
aws eks update-kubeconfig --name <nonprod-cluster> --alias pc2-nonprod --region us-east-2
kubectl --context pc2-nonprod apply -f aws/k8s-apps/dcf-crd/nonprod-namespaces.yaml
kubectl --context pc2-nonprod apply -f aws/k8s-apps/dcf-crd/firewallpolicy-nonprod.yaml
```

## Traffic Tests

```bash
# Deploy test pods in both clusters
for ctx in pc2-prod pc2-nonprod; do
  kubectl --context $ctx -n default run nginx --image=nginx:alpine --port=80 --restart=Never
  kubectl --context $ctx -n default run netshoot --image=nicolaka/netshoot --command -- sleep infinity --restart=Never
done
```

Expected results:

| Test | Expected | DCF Rule |
|---|---|---|
| prod → nonprod VPC | BLOCKED | DENY 10 |
| nonprod → prod VPC | BLOCKED | DENY 11 |
| nonprod → DB spoke | BLOCKED | DENY 30 |
| prod → DB spoke | PASS | PERMIT 31 |
| prod egress registry.k8s.io | PASS | PERMIT 50 |
| nonprod egress registry.k8s.io | PASS | PERMIT 51 |

## Destroy (reverse order)

```bash
# Layer 4
kubectl --context pc2-prod delete -f aws/k8s-apps/dcf-crd/
kubectl --context pc2-nonprod delete -f aws/k8s-apps/dcf-crd/

# Layer 3
terraform -chdir=aws/nodes/prod destroy -auto-approve &
terraform -chdir=aws/nodes/nonprod destroy -auto-approve &
wait

# Layer 2
terraform -chdir=aws/clusters/prod destroy -var="aviatrix_aws_account_name=<account>" -auto-approve &
terraform -chdir=aws/clusters/nonprod destroy -var="aviatrix_aws_account_name=<account>" -auto-approve &
wait

# Layer 1
terraform -chdir=aws/network destroy -var="aws_account_name=<account>" -auto-approve
```

## Key Design Notes

- **Two-layer isolation is the key differentiator** — environment boundary (VPC) prevents gross misconfiguration; namespace boundary enforces team segmentation within each environment
- **Database spoke is prod-only via transit routing + DCF** — dual enforcement means a misconfigured DCF rule alone can't expose the DB to nonprod
- **`k8s_cluster_id` differs for prod vs nonprod SmartGroups** — without this, namespace names collide between clusters
- **Sandbox namespace has relaxed egress** — suitable for developer experimentation without compromising prod or nonprod
- **HA enabled by default** — recommended for production-grade deployments

## Environment Policies

| Namespace | Egress Allowed | Rationale |
|---|---|---|
| team-a-prod | Stripe, Datadog, AWS APIs | Production: strict allowlist |
| team-b-prod | CloudFront, Akamai | Production: CDN only |
| team-a-dev | npm, GitHub, AWS, Stripe | Dev: includes build tools |
| team-b-staging | Staging CDN, build tools | Staging: mirrors prod with extras |
| sandbox | All HTTPS | Developer experimentation |

## When to Use

**Recommended for most organizations.** Choose this pattern when you need environment-level isolation (prod cannot talk to nonprod) combined with team self-service egress policies. Balances security, cost, and operational overhead.

For the strongest isolation, see [k8s-cluster-aas](../k8s-cluster-aas/). For the lowest cost, see [k8s-namespace-aas](../k8s-namespace-aas/).
