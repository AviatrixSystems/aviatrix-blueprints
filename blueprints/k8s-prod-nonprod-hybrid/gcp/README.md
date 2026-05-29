# k8s-prod-nonprod-hybrid — GCP (GKE)

This blueprint deploys a production and non-production GKE environment on GCP secured by the **Aviatrix Cloud Native Security Fabric (CNSF)**. It implements two-layer Distributed Cloud Firewall (DCF) isolation: environment-level enforcement via VPC SmartGroups, and namespace-level Zero Trust segmentation via Kubernetes SmartGroups — giving teams self-service egress control through FirewallPolicy CRDs while maintaining a hard boundary between prod and nonprod.

> [!TIP]
> **Optimized for Claude Code** — Run `/deploy-blueprint` for AI-guided deployment with prerequisite checks, or `/analyze-blueprint` for resource and cost details.

---

## Architecture

```
Transit GW (10.28.0.0/20, HA)
├── Prod Spoke    (10.10.0.0/20) ──── GKE prod-cluster
│                                         ├── namespace: team-a-prod
│                                         ├── namespace: team-b-prod
│                                         └── namespace: monitoring
├── NonProd Spoke (10.20.0.0/20) ──── GKE nonprod-cluster
│                                         ├── namespace: team-a-dev
│                                         ├── namespace: team-b-staging
│                                         ├── namespace: sandbox
│                                         └── namespace: monitoring
└── DB Spoke      (10.45.0.0/22)  ──── Database (prod-only)
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
| 50 | PERMIT | all-clusters egress HTTPS (GKE required GCP services) |
| 51 | PERMIT | sandbox egress HTTPS (relaxed, all hosts) |
| 70–99 | — | Reserved: team self-service via FirewallPolicy CRDs |

> **GCP note:** GKE node pools must have the `avx-snat-noip` network tag to route pod egress through the Aviatrix spoke gateway. This is applied automatically in the nodes layer.

---

## Prerequisites

### Aviatrix Infrastructure

| Component | Requirement | Notes |
|---|---|---|
| **Aviatrix Controller** | v8.x, provider ~> 8.2 | Must be deployed and reachable |
| **Aviatrix CoPilot** | Recommended | Required for DCF visualization and SmartGroups UI |
| **GCP Account Onboarded** | Account registered in Controller | Use exact account name as `gcp_account_name` variable |

### Local Tools

| Tool | Version | Installation |
|---|---|---|
| **Terraform** | >= 1.5 | https://developer.hashicorp.com/terraform/install |
| **gcloud CLI** | Latest | https://cloud.google.com/sdk/docs/install |
| **kubectl** | Latest | https://kubernetes.io/docs/tasks/tools/ |
| **helm** | v3 | https://helm.sh/docs/intro/install/ |

### GCP IAM Permissions

The GCP service account or user must have:
- `roles/container.admin` — GKE cluster and node pool management
- `roles/compute.networkAdmin` — VPC, subnets, routes, firewall rules
- `roles/iam.serviceAccountAdmin` — Service account creation and IAM binding
- `roles/dns.admin` — Cloud DNS private zones and record sets

### Environment Variables

```bash
# Aviatrix Controller credentials
export AVIATRIX_CONTROLLER_IP="your-controller.example.com"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="your-password"

# GCP credentials — choose one method
# Option 1: Application Default Credentials (recommended for local dev)
gcloud auth application-default login

# Option 2: Service account key file
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"

# Set default project
export GOOGLE_PROJECT="<your-gcp-project-id>"
```

---

## Resources Created

| Resource | Qty | Estimated $/hr |
|---|---|---|
| `aviatrix_transit_gateway` (n1-standard-4, HA) | 2 | ~$0.38 |
| `aviatrix_spoke_gateway` (n1-standard-2, HA each) | 6 | ~$0.60 |
| `aviatrix_vpc` (VPCs) | 3 | — |
| `aviatrix_distributed_firewalling_config` | 1 (if `manage_dcf=true`) | — |
| `aviatrix_k8s_config` | 1 (if `manage_dcf=true`) | — |
| `aviatrix_smart_group` | 11 | — |
| `aviatrix_web_group` | 3 | — |
| `aviatrix_dcf_ruleset` | 1 | — |
| `google_container_cluster` (prod + nonprod) | 2 | ~$0.10 each |
| `google_container_node_pool` (e2-standard-4 × 2) | 2 | ~$0.13/node/hr |
| `google_dns_managed_zone` (private) | 1 | ~$0.20/month |
| `helm_release` (ExternalDNS + k8s-firewall per cluster) | 4 | — |

**Estimated total: ~$1.60/hr** (HA enabled, us-central1 pricing)

> Disable HA (`enable_ha = false`) to approximately halve the Aviatrix gateway cost.

---

## Deployment Instructions

### Layer 1 — Network (~8 min)

```bash
cd gcp/network

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set gcp_account_name and gcp_project

terraform init
terraform apply
```

### Layer 2 — Clusters (parallel, ~10 min)

```bash
cd gcp/clusters/prod
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set gcp_project and aviatrix_gcp_account_name
terraform init
terraform apply &

cd ../../clusters/nonprod
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply &
wait
```

### Layer 3 — Nodes (parallel, ~5 min)

```bash
cd gcp/nodes/prod
terraform init
terraform apply &

cd ../nonprod
terraform init
terraform apply &
wait
```

**What is created:** GKE node pools (with `avx-snat-noip` tag), `aviatrix_kubernetes_cluster` registration, ExternalDNS helm chart, k8s-firewall helm chart (for DCF Layer 2 enforcement).

### Layer 4 — K8s Apps

Get cluster credentials and apply CRDs:

```bash
GCP_PROJECT=$(cd gcp/network && terraform output -raw gcp_project 2>/dev/null || echo $GOOGLE_PROJECT)
GCP_REGION="us-central1"

PROD_CLUSTER=$(cd gcp/clusters/prod && terraform output -raw cluster_name)
NONPROD_CLUSTER=$(cd gcp/clusters/nonprod && terraform output -raw cluster_name)

# Configure kubectl contexts
gcloud container clusters get-credentials "$PROD_CLUSTER" \
  --region "$GCP_REGION" --project "$GCP_PROJECT"
kubectl config rename-context \
  "gke_${GCP_PROJECT}_${GCP_REGION}_${PROD_CLUSTER}" pc2-prod 2>/dev/null || true

gcloud container clusters get-credentials "$NONPROD_CLUSTER" \
  --region "$GCP_REGION" --project "$GCP_PROJECT"
kubectl config rename-context \
  "gke_${GCP_PROJECT}_${GCP_REGION}_${NONPROD_CLUSTER}" pc2-nonprod 2>/dev/null || true

# Apply namespace manifests
kubectl --context pc2-prod apply -f gcp/k8s-apps/dcf-crd/prod-namespaces.yaml
kubectl --context pc2-nonprod apply -f gcp/k8s-apps/dcf-crd/nonprod-namespaces.yaml

# Apply FirewallPolicy CRDs
kubectl --context pc2-prod apply -f gcp/k8s-apps/dcf-crd/firewallpolicy-prod.yaml
kubectl --context pc2-nonprod apply -f gcp/k8s-apps/dcf-crd/firewallpolicy-nonprod.yaml
```

### Update Network Layer with Cluster IDs (Two-Pass Deployment)

After clusters register with the Controller, get the Aviatrix cluster IDs and re-apply the network layer:

```bash
# Get cluster IDs: CoPilot → Security → DCF → SmartGroups → create a K8s SmartGroup
# The Controller will list available cluster IDs.

cd gcp/network
# Add to terraform.tfvars:
#   prod_cluster_id    = "<id-from-copilot>"
#   nonprod_cluster_id = "<id-from-copilot>"
terraform apply
```

---

## Variables Reference

### Network (`gcp/network/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `gcp_account_name` | `string` | — | yes | Aviatrix GCP account name (as registered in Controller) |
| `gcp_project` | `string` | — | yes | GCP project ID |
| `gcp_region` | `string` | `us-central1` | no | GCP region for all resources |
| `transit_cidr` | `string` | `10.28.0.0/20` | no | Transit VPC CIDR |
| `prod_vpc_cidr` | `string` | `10.10.0.0/20` | no | Production VPC CIDR |
| `nonprod_vpc_cidr` | `string` | `10.20.0.0/20` | no | Non-production VPC CIDR |
| `db_spoke_cidr` | `string` | `10.45.0.0/22` | no | Database spoke CIDR (prod-only) |
| `pod_cidr` | `string` | `100.64.0.0/16` | no | Secondary CIDR for pod networking (VPC-native) |
| `services_cidr` | `string` | `172.40.0.0/20` | no | Secondary range for Kubernetes services |
| `name_prefix` | `string` | `pc2` | no | Prefix for all resource names |
| `enable_ha` | `bool` | `true` | no | Enable HA for all gateways |
| `prod_cluster_id` | `string` | `""` | no | Aviatrix cluster ID for prod GKE (set after clusters/ deploy) |
| `nonprod_cluster_id` | `string` | `""` | no | Aviatrix cluster ID for nonprod GKE (set after clusters/ deploy) |
| `random_suffix` | `bool` | `true` | no | Append random hex to resource names |
| `manage_dcf` | `bool` | `false` | no | Set `true` only if DCF is not already enabled on this Controller |

### Clusters (`gcp/clusters/prod/` and `gcp/clusters/nonprod/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `gcp_project` | `string` | — | yes | GCP project ID |
| `aviatrix_gcp_account_name` | `string` | — | yes | Aviatrix GCP account name |
| `kubernetes_version` | `string` | `1.31` | no | Kubernetes version for GKE |
| `release_channel` | `string` | `REGULAR` | no | GKE release channel |
| `master_ipv4_cidr_block` | `string` | see tfvars | no | GKE control plane CIDR (/28, unique per cluster) |

### Nodes (`gcp/nodes/prod/` and `gcp/nodes/nonprod/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `node_count` | `number` | `2` | no | Number of nodes per node pool |
| `machine_type` | `string` | `e2-standard-4` | no | GCE machine type for worker nodes |
| `cluster_name` | `string` | — | yes | GKE cluster name (from clusters layer output) |
| `cluster_endpoint` | `string` | — | yes | GKE API server endpoint |
| `cluster_ca_certificate` | `string` | — | yes | Base64 cluster CA certificate |
| `cluster_id` | `string` | — | yes | Full GKE cluster resource ID (for Aviatrix registration) |
| `aviatrix_controller_ip` | `string` | — | yes | Aviatrix Controller IP |
| `aviatrix_username` | `string` | `admin` | no | Aviatrix Controller username |
| `aviatrix_password` | `string` | — | yes | Aviatrix Controller password (sensitive) |

---

## Test Scenarios

### Scenario 1 — Environment isolation (nonprod → prod blocked)

```bash
kubectl run --context=pc2-prod server --image=nginx --port=80 --expose

# From nonprod, try to reach prod VPC (should be blocked — DCF DENY priority 11)
kubectl run --context=pc2-nonprod test --rm -it --image=curlimages/curl --restart=Never -- \
  curl --connect-timeout 5 http://10.10.0.100  # prod VPC IP
# Expected: connection timeout
```

### Scenario 2 — DB access (prod only)

```bash
# From prod, reach DB (should succeed — DCF PERMIT priority 20)
kubectl run --context=pc2-prod db-test --rm -it --image=mysql:8 --restart=Never -- \
  mysql -h 10.45.0.10 -u testuser -p --connect-timeout=5
# Expected: connection (or auth failure — not network timeout)

# From nonprod, reach DB (should be blocked — DCF DENY priority 21)
kubectl run --context=pc2-nonprod db-test --rm -it --image=mysql:8 --restart=Never -- \
  mysql -h 10.45.0.10 -u testuser -p --connect-timeout=5
# Expected: connection timeout
```

### Scenario 3 — Monitoring scrape

```bash
kubectl run --context=pc2-prod monitor-test -n monitoring --rm -it \
  --image=curlimages/curl --restart=Never -- \
  curl http://team-a-service.team-a-prod:9090
# Expected: HTTP response
```

### Scenario 4 — Sandbox relaxed egress

```bash
kubectl run --context=pc2-nonprod sandbox-test -n sandbox --rm -it \
  --image=curlimages/curl --restart=Never -- \
  curl https://example.com
# Expected: HTTP response (sandbox has relaxed egress at priority 51)
```

---

## Cleanup / Destroy

**Destroy in reverse layer order.**

### Step 1 — Clean up Kubernetes resources

```bash
for ctx in pc2-prod pc2-nonprod; do
  kubectl delete ingress --all -A --context=$ctx 2>/dev/null || true
  kubectl delete svc -A --field-selector spec.type=LoadBalancer --context=$ctx 2>/dev/null || true
done
```

### Step 2 — Destroy Layer 3: Nodes (parallel)

```bash
terraform -chdir=gcp/nodes/prod destroy -auto-approve &
terraform -chdir=gcp/nodes/nonprod destroy -auto-approve &
wait
```

### Step 3 — Destroy Layer 2: Clusters (parallel)

```bash
terraform -chdir=gcp/clusters/prod destroy -auto-approve &
terraform -chdir=gcp/clusters/nonprod destroy -auto-approve &
wait
```

### Step 4 — Destroy Layer 1: Network

```bash
terraform -chdir=gcp/network destroy -auto-approve
```

---

## Troubleshooting

**`avx-snat-noip` tag not applied — pods cannot reach internet**

GKE node pools must have the network tag `avx-snat-noip` to route pod egress through the Aviatrix spoke gateway. This tag is set in the nodes layer `google_container_node_pool` resource. If nodes lack the tag, destroy and re-apply the nodes layer.

**GKE master CIDR conflict**

Each cluster requires a unique `/28` master CIDR block. Use non-overlapping CIDRs for prod and nonprod (e.g. `172.16.0.0/28` and `172.16.0.16/28`). These must not overlap with any other subnet in the VPC or transit.

**Namespace SmartGroups not enforcing**

K8s namespace SmartGroups require `prod_cluster_id` and `nonprod_cluster_id` in the network layer `terraform.tfvars`. Run the two-pass deployment: clusters first, then get the cluster IDs from CoPilot and re-apply the network layer.

**`aviatrix_kubernetes_cluster` fails: cluster not found**

Wait 2–5 minutes after GKE node pools join for the Aviatrix Controller to complete its Kubernetes inventory sync. Re-run `terraform apply` in the nodes layer if this fails.

**DCF rules not enforcing**

Verify DCF is `Enabled` in CoPilot → Security → DCF. If `manage_dcf = false`, DCF must have been enabled externally before deploying this blueprint.

---

## Tested With

| Component | Version |
|---|---|
| Aviatrix Controller | 7.2+ |
| Aviatrix Terraform Provider | ~> 8.2.0 |
| Terraform | >= 1.5 |
| Google Provider | ~> 6.0 |
| Kubernetes Provider | ~> 2.20 |
| Helm Provider | ~> 2.x |
| Kubernetes | 1.31 (GKE) |
