# Kubernetes Cluster-as-a-Service — GCP (GKE)

Each team gets a **dedicated GKE cluster in its own VPC**. Workload isolation is enforced by the **Aviatrix Cloud Native Security Fabric (CNSF)** — Distributed Cloud Firewall (DCF) at the VPC boundary — so no team can reach another team's cluster without an explicit PERMIT rule. This blueprint demonstrates VPC-level SmartGroup segmentation, post-SNAT DCF enforcement, GeoBlock/ThreatIQ threat prevention, and egress control via WebGroups.

---

## Architecture Diagram

![Architecture Diagram](../architecture.svg)

**Data flow:** Pods use VPC-native networking with an RFC 6598 overlay CIDR (`100.64.0.0/16`). Each spoke gateway applies custom SNAT (`avx-snat-noip` node tag routes pod traffic through the Aviatrix spoke gateway), translating pod IPs to the spoke gateway's private IP. DCF evaluates **post-SNAT traffic** — use VPC-type SmartGroups to identify source teams, and hostname-type SmartGroups to identify service destinations.

```
Internet
    │ (blocked by default unless WebGroup permits)
    ▼
Transit GW (10.38.0.0/20)  ◄── DCF evaluates here (post-SNAT)
├── Team-A Spoke (10.40.0.0/20) ── GKE cluster-a  [pods: 100.64.0.0/18]
├── Team-B Spoke (10.41.0.0/20) ── GKE cluster-b  [pods: 100.64.64.0/18]
├── Team-C Spoke (10.42.0.0/20) ── GKE cluster-c  [pods: 100.64.128.0/18]
└── DB Spoke    (10.45.0.0/22)  ── Shared database
```

### DCF Policy Layout

| Priority | Action | Rule |
|---|---|---|
| 0 | DENY | Geo-block (IR, KP, RU) |
| 1 | DENY | ThreatIQ (major + critical) |
| 10 | PERMIT | team-a → team-b TCP/443 |
| 11 | PERMIT | team-b → team-a TCP/8080 |
| 20 | DENY | team-a → team-c (bidirectional at 20–23) |
| 50 | PERMIT | all clusters → GKE required GCP services (TCP/443) |

> **Note:** GKE nodes must have the `avx-snat-noip` network tag to route pod egress through the Aviatrix spoke gateway. This is set automatically in the nodes layer.

---

## Prerequisites

### Aviatrix Infrastructure

| Component | Requirement | Notes |
|---|---|---|
| **Aviatrix Controller** | Version compatible with provider ~> 8.2 | Must be deployed and reachable |
| **Aviatrix CoPilot** | Recommended | Required for DCF visualization and SmartGroups UI |
| **GCP Account Onboarded** | Account registered in Controller | Use the exact account name in `terraform.tfvars` |

### Local Tools

| Tool | Version | Installation | Purpose |
|---|---|---|---|
| **Terraform** | >= 1.5 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure provisioning |
| **gcloud CLI** | Latest | [Install Guide](https://cloud.google.com/sdk/docs/install) | GCP authentication and GKE kubeconfig |
| **kubectl** | Latest | [Install Guide](https://kubernetes.io/docs/tasks/tools/) | Kubernetes cluster interaction |

### GCP IAM Permissions

The GCP service account or user must have the following roles:
- `roles/container.admin` — GKE cluster and node pool management
- `roles/compute.networkAdmin` — VPC, subnets, routes, firewall rules
- `roles/compute.securityAdmin` — IAM service account binding (for Workload Identity)
- `roles/iam.serviceAccountAdmin` — Service account creation and IAM binding
- `roles/dns.admin` — Cloud DNS private zones and record sets

### Environment Variables

```bash
# Aviatrix Controller credentials
export AVIATRIX_CONTROLLER_IP="<controller-ip-or-hostname>"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="<password>"

# GCP credentials — choose one method
# Option 1: Application Default Credentials (recommended for local dev)
gcloud auth application-default login

# Option 2: Service account key file
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"

# GCP project
export GOOGLE_PROJECT="<your-gcp-project-id>"
```

---

## Resources Created

| Resource | Count | Est. Hourly Cost |
|---|---|---|
| `aviatrix_transit_gateway` (n1-standard-4) | 1 | ~$0.19 |
| `aviatrix_spoke_gateway` (n1-standard-2, no HA) | 3 | ~$0.05 each |
| `aviatrix_vpc` (transit + 3 team + DB) | 5 | — |
| `aviatrix_spoke_transit_attachment` | 4 | — |
| `aviatrix_gateway_snat` | 3 | — |
| `aviatrix_distributed_firewalling_config` | 0 or 1 | — |
| `aviatrix_k8s_config` | 0 or 1 | — |
| `aviatrix_kubernetes_cluster` | 3 | — |
| `aviatrix_smart_group` | 9 | — |
| `aviatrix_web_group` | 3 | — |
| `aviatrix_dcf_ruleset` | 1 | — |
| `google_container_cluster` (VPC-native, private) | 3 | ~$0.10 each |
| `google_container_node_pool` (e2-standard-4 × 2) | 3 | ~$0.13/node/hr |
| `google_dns_managed_zone` (private) | 1 | ~$0.20/month |
| `helm_release` (ExternalDNS + k8s-firewall per cluster) | 6 | — |

**Estimated total:** ~$1.20/hour (3 clusters, 2 nodes each, us-central1 pricing).

> Aviatrix licensing costs are separate and depend on your subscription type.

---

## Deployment Instructions

### Step 1 — Set environment variables

```bash
export AVIATRIX_CONTROLLER_IP="<controller-ip>"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="<password>"
gcloud auth application-default login

# Verify GCP credentials
gcloud config get-value project
```

### Step 2 — Deploy Layer 1: Network (~10 min)

```bash
cd gcp/network
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set aviatrix_gcp_account_name and gcp_project
vim terraform.tfvars

terraform init
terraform apply
```

**What is created:** Aviatrix transit gateway, 4 VPCs (transit + 3 team + DB), 3 spoke gateways, spoke-to-transit attachments, custom SNAT rules (pod CIDR → spoke GW IP), Cloud DNS private zone, and the DCF ruleset.

### Step 3 — Deploy Layer 2: GKE Clusters (parallel, ~10 min)

```bash
for team in team-a team-b team-c; do
  cd gcp/clusters/$team
  cp terraform.tfvars.example terraform.tfvars
  # Edit terraform.tfvars: set gcp_project and aviatrix_gcp_account_name
  terraform init
  terraform apply -auto-approve &
  cd ../../..
done
wait
```

**What is created:** GKE cluster per team (VPC-native, private nodes, Workload Identity enabled), OIDC issuer, service account bindings for ExternalDNS and the k8s-firewall agent.

> **Note:** `terraform.tfvars.example` in each cluster directory contains required variables. Copy and fill in GCP project and account values before applying.

### Step 4 — Deploy Layer 3: Node Pools (parallel, ~5 min)

```bash
for team in team-a team-b team-c; do
  cd gcp/nodes/$team
  terraform init
  terraform apply -auto-approve &
  cd ../../..
done
wait
```

**What is created:** GKE node pools (with `avx-snat-noip` tag for Aviatrix spoke gateway SNAT), `aviatrix_kubernetes_cluster` registration, ExternalDNS helm chart, k8s-firewall helm chart.

### Step 5 — Configure kubectl

```bash
GCP_PROJECT=$(cd gcp/network && terraform output -raw gcp_project 2>/dev/null || echo $GOOGLE_PROJECT)
GCP_REGION="us-central1"

for team in team-a team-b team-c; do
  cluster_name=$(cd gcp/clusters/$team && terraform output -raw cluster_name)
  gcloud container clusters get-credentials "$cluster_name" \
    --region "$GCP_REGION" \
    --project "$GCP_PROJECT"
  kubectl config rename-context \
    "gke_${GCP_PROJECT}_${GCP_REGION}_${cluster_name}" \
    "$team" 2>/dev/null || true
done

# Verify all three clusters are accessible
kubectl config get-contexts
kubectl get nodes --context=team-a
kubectl get nodes --context=team-b
kubectl get nodes --context=team-c
```

---

## Variables Reference

### Network (`gcp/network/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `aviatrix_gcp_account_name` | string | — | yes | GCP account name as registered in Aviatrix Controller |
| `gcp_project` | string | — | yes | GCP project ID for all resources |
| `gcp_region` | string | `us-central1` | no | GCP region for all resources |
| `name_prefix` | string | `caas` | no | Prefix for all resource names |
| `transit_cidr` | string | `10.38.0.0/20` | no | CIDR for the Aviatrix transit VPC |
| `team_a_vpc_cidr` | string | `10.40.0.0/20` | no | Primary CIDR for team-a GKE VPC |
| `team_b_vpc_cidr` | string | `10.41.0.0/20` | no | Primary CIDR for team-b GKE VPC |
| `team_c_vpc_cidr` | string | `10.42.0.0/20` | no | Primary CIDR for team-c GKE VPC |
| `db_vpc_cidr` | string | `10.45.0.0/22` | no | CIDR for the database spoke VPC |
| `pod_cidr` | string | `100.64.0.0/16` | no | Secondary range for pod networking (RFC 6598) |
| `services_cidr` | string | `172.40.0.0/20` | no | Secondary range for Kubernetes services |
| `team_a_master_cidr` | string | `172.16.0.0/28` | no | GKE master CIDR for team-a (must be unique /28) |
| `team_b_master_cidr` | string | `172.16.0.16/28` | no | GKE master CIDR for team-b |
| `team_c_master_cidr` | string | `172.16.0.32/28` | no | GKE master CIDR for team-c |
| `dns_private_zone_name` | string | `gcp.aviatrixdemo.local` | no | Cloud DNS private zone name |
| `random_suffix` | bool | `true` | no | Append random hex suffix to all resource names |
| `manage_dcf` | bool | `false` | no | Whether this blueprint manages DCF global enable/disable |

### Cluster (`gcp/clusters/team-*/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `gcp_project` | string | — | yes | GCP project ID |
| `aviatrix_gcp_account_name` | string | — | yes | Aviatrix GCP account name |
| `kubernetes_version` | string | `1.31` | no | Kubernetes version for GKE release channel |
| `release_channel` | string | `REGULAR` | no | GKE release channel (`RAPID`, `REGULAR`, `STABLE`) |

### Nodes (`gcp/nodes/team-*/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `node_count` | number | `2` | no | Number of nodes in the node pool |
| `machine_type` | string | `e2-standard-4` | no | GCE machine type for worker nodes |
| `cluster_name` | string | — | yes | GKE cluster name (from clusters layer output) |
| `cluster_endpoint` | string | — | yes | GKE API server endpoint |
| `cluster_ca_certificate` | string | — | yes | Base64 cluster CA certificate (from clusters layer output) |
| `aviatrix_controller_ip` | string | — | yes | Aviatrix Controller IP (for k8s-firewall helm values) |
| `aviatrix_username` | string | `admin` | no | Aviatrix Controller username |
| `aviatrix_password` | string | — | yes | Aviatrix Controller password (sensitive) |

---

## Outputs Reference

### Network (`gcp/network/`)

| Output | Description |
|---|---|
| `transit_gateway_name` | Aviatrix transit gateway name (sensitive) |
| `team_a_vpc_name` | Team-A GCP VPC network name |
| `team_a_spoke_gateway_name` | Team-A spoke gateway name (sensitive) |
| `team_a_cluster_name` | Team-A GKE cluster name |
| `team_b_vpc_name` | Team-B GCP VPC network name |
| `team_b_spoke_gateway_name` | Team-B spoke gateway name (sensitive) |
| `team_b_cluster_name` | Team-B GKE cluster name |
| `team_c_vpc_name` | Team-C GCP VPC network name |
| `team_c_spoke_gateway_name` | Team-C spoke gateway name (sensitive) |
| `team_c_cluster_name` | Team-C GKE cluster name |
| `dns_private_zone_name` | Cloud DNS private zone name |
| `dcf_ruleset_uuid` | UUID of the DCF ruleset |
| `gcp_project` | GCP project ID |

### Cluster (`gcp/clusters/team-*/`)

| Output | Description |
|---|---|
| `cluster_name` | GKE cluster name |
| `cluster_endpoint` | GKE API server endpoint |
| `cluster_ca_certificate` | Base64 encoded cluster CA certificate (sensitive) |
| `cluster_id` | Full GKE cluster resource ID (used for Aviatrix k8s registration) |
| `workload_identity_pool` | GCP Workload Identity pool for this cluster |

### Nodes (`gcp/nodes/team-*/`)

Nodes workspaces expose no outputs — node pools are consumed by Kubernetes directly.

---

## Test Scenarios

### Scenario 1 — Permitted east-west traffic (team-a → team-b on TCP/443)

```bash
kubectl run --context=team-b server --image=nginx --port=443 --expose

kubectl run --context=team-a test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -k https://team-b.gcp.aviatrixdemo.local
# Expected: HTTP response
```

### Scenario 2 — Blocked east-west traffic (team-a → team-c, any port)

```bash
kubectl run --context=team-a test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -k --connect-timeout 5 https://team-c.gcp.aviatrixdemo.local
# Expected: connection timeout
```

### Scenario 3 — Permitted egress to GKE required services

```bash
kubectl run --context=team-a test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -k --connect-timeout 5 https://registry.k8s.io
# Expected: HTTP response (not blocked)
```

### Scenario 4 — GeoBlock enforcement

Verify in CoPilot → Security → Distributed Cloud Firewall → Traffic Logs that traffic to geo-blocked countries (IR, KP, RU) is logged as DENY with rule `caas-block-geo`.

---

## Cleanup / Destroy

**Destroy in reverse layer order.** Destroying the network layer while clusters still exist will leave orphaned Aviatrix resources.

### Step 1 — Clean up Kubernetes resources

```bash
for team in team-a team-b team-c; do
  kubectl delete ingress --all -A --context=$team 2>/dev/null || true
  kubectl delete svc -A --field-selector spec.type=LoadBalancer --context=$team 2>/dev/null || true
done
# Wait ~60 seconds for ExternalDNS to clean up Cloud DNS records
```

### Step 2 — Destroy Layer 3: Nodes (parallel)

```bash
for team in team-a team-b team-c; do
  terraform -chdir=gcp/nodes/$team destroy -auto-approve &
done
wait
```

### Step 3 — Destroy Layer 2: Clusters (parallel)

```bash
for team in team-a team-b team-c; do
  terraform -chdir=gcp/clusters/$team destroy -auto-approve &
done
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

**`aviatrix_kubernetes_cluster` fails: cluster not found**

Wait 2–5 minutes after node pools join for the Aviatrix Controller to complete its Kubernetes inventory sync. The Controller polls GKE clusters periodically. Re-run `terraform apply` in the nodes layer if this fails.

**GKE master CIDR conflict**

Each cluster requires a unique `/28` master CIDR (`team_a_master_cidr`, `team_b_master_cidr`, `team_c_master_cidr`). These must not overlap with any other subnet in the VPC or transit. The defaults `172.16.0.0/28`, `172.16.0.16/28`, `172.16.0.32/28` are safe for most deployments.

**Pods cannot reach external services**

1. Verify the node tag `avx-snat-noip` is present on nodes: `kubectl get nodes -o wide`
2. Verify SNAT rules in Aviatrix Controller → Gateways → [spoke gateway] → SNAT
3. Verify the DCF egress PERMIT rule (priority 50) allows traffic to `*.googleapis.com` and `registry.k8s.io`

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
