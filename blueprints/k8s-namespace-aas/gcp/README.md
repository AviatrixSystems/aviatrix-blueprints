# Namespace-as-a-Service — GCP (GKE)

All teams share a **single GKE cluster** with namespace-level workload isolation enforced by the **Aviatrix Cloud Native Security Fabric (CNSF)** — Distributed Cloud Firewall (DCF) at the transit layer. Kubernetes RBAC prevents accidental cross-namespace access but is not a security boundary; DCF is the enforcement mechanism.

---

## Architecture Diagram

<!-- TODO: Add architecture diagram — place architecture.png or architecture.svg in this directory -->

```
Transit VPC (10.38.0.0/20)
  Aviatrix Transit GW
      │
      └── Shared Spoke VPC (10.40.0.0/16)
              Aviatrix Spoke GW (SNAT: 100.64.0.0/16 → spoke-ip)
                  │
                  └── GKE Shared Cluster (VPC-native alias IPs)
                          ├── namespace: team-a  [pods: 100.64.x.x]
                          ├── namespace: team-b  [pods: 100.64.x.x]
                          └── namespace: team-c  [pods: 100.64.x.x]
```

Pod traffic uses GKE VPC-native networking with alias IP ranges from the RFC 6598 CIDR (`100.64.0.0/16`). The Aviatrix spoke gateway SNATs pod IPs to the spoke gateway IP before entering the transit. DCF SmartGroups match on the originating Kubernetes namespace. GKE nodes carry the `avx-snat-noip` tag to ensure internet egress routes through the Aviatrix gateway.

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
| 60 | PERMIT | All namespaces → public internet (GKE required + approved domains, TCP/443) |
| 70–99 | (reserved) | CRD-managed team self-service rules (GitOps) |

---

## Prerequisites

### Aviatrix Controller

| Requirement | Details |
|---|---|
| Aviatrix Controller | Version compatible with provider ~> 8.2; must be running and accessible |
| Aviatrix CoPilot | Recommended for DCF visualization and SmartGroups UI |
| GCP Account Onboarded | Account name registered in the Controller (used for `aviatrix_gcp_account_name`) |
| DCF Enabled | Either pre-enabled by your Controller admin OR set `manage_dcf = true` if this blueprint owns DCF lifecycle |

### Local Tools

| Tool | Min Version | Notes |
|---|---|---|
| Terraform | >= 1.5 | [Install](https://developer.hashicorp.com/terraform/install) |
| Google Cloud SDK (gcloud) | Latest | [Install](https://cloud.google.com/sdk/docs/install) — used for GKE credentials |
| kubectl | Latest | [Install](https://kubernetes.io/docs/tasks/tools/) |
| helm | Latest | [Install](https://helm.sh/docs/intro/install/) |

### GCP IAM Permissions

The service account used by Terraform must have the following roles (or equivalent custom roles) in the target project:
- `roles/container.admin` — create and manage GKE clusters
- `roles/compute.admin` — manage VPCs, subnets, firewall rules
- `roles/dns.admin` — manage Cloud DNS private zones
- `roles/iam.serviceAccountAdmin` — create service accounts for Workload Identity
- `roles/iam.workloadIdentityPoolAdmin` — configure Workload Identity Federation
- `roles/resourcemanager.projectIamAdmin` — bind IAM roles on the project

> `roles/owner` covers all required permissions for demo environments. For production, use a scoped-down custom role.

### Environment Variables

```bash
# Aviatrix Controller
export AVIATRIX_CONTROLLER_IP="your-controller-ip"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="your-password"

# GCP credentials (choose one method)
# Option 1: Application Default Credentials (recommended)
gcloud auth application-default login
gcloud config set project your-project-id

# Option 2: Service account key file
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
export GOOGLE_PROJECT="your-project-id"
```

---

## Resources Created

| Resource | Qty | Estimated hourly cost |
|---|---|---|
| `aviatrix_transit_gateway` | 1 | ~$0.17/hr |
| `aviatrix_vpc` (transit VPC) | 1 | — |
| `aviatrix_spoke_gateway` (shared, no HA) | 1 | ~$0.04/hr |
| `aviatrix_spoke_transit_attachment` | 1 | — |
| `aviatrix_distributed_firewalling_config` | 0 or 1 | — (only if manage_dcf=true) |
| `aviatrix_k8s_config` | 0 or 1 | — (only if manage_dcf=true) |
| `aviatrix_kubernetes_cluster` | 1 | — |
| `aviatrix_smart_group` | 7 | — |
| `aviatrix_web_group` | 2 | — |
| `aviatrix_dcf_ruleset` | 1 | — |
| `google_container_cluster` (GKE) | 1 | ~$0.10/hr (control plane) |
| GKE node VMs (3× e2-standard-4 Spot) | 3 | ~$0.04–0.06/hr each |
| `google_dns_managed_zone` (private) | 1 | ~$0.20/mo |
| `google_service_account` (ExternalDNS, GKE node) | 2 | — |
| `helm_release` (ExternalDNS) | 1 | — |

> Estimated cost at defaults (us-central1, 3 Spot nodes, no HA): roughly **$0.45–0.60/hr** (~$330–440/month). Aviatrix licensing is billed separately.

---

## Deployment Instructions

### Step 0 — Set environment variables

```bash
export AVIATRIX_CONTROLLER_IP="your-controller-ip"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="your-password"

# Verify GCP credentials
gcloud auth list
gcloud config get-value project
```

### Step 1 — Layer 1: Network (~12 min)

```bash
cd gcp/network

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   aviatrix_gcp_account_name = "your-aviatrix-account-name"
#   gcp_project               = "your-gcp-project-id"
#   gcp_region                = "us-central1"
#   # Leave k8s_cluster_id empty for now — fill in after Step 2

terraform init
terraform apply -var-file=terraform.tfvars
```

### Step 2 — Layer 2: Shared GKE Cluster (~12 min)

```bash
cd gcp/clusters/shared

cp terraform.tfvars.example terraform.tfvars
# Edit if needed (all variables have defaults)

terraform init
terraform apply -var-file=terraform.tfvars

# Note the cluster_id output — needed for DCF SmartGroups
terraform output cluster_id
```

### Step 2b — Update network layer with cluster ID (SmartGroups)

```bash
cd gcp/network

# Edit terraform.tfvars:
#   k8s_cluster_id = "<cluster_id from Step 2>"
#   # Format: https://container.googleapis.com/v1/projects/{project}/locations/{location}/clusters/{name}

terraform apply -var-file=terraform.tfvars
```

### Step 3 — Layer 3: Node Pool + Helm Add-ons (~10 min)

```bash
cd gcp/nodes/shared

terraform init
terraform apply
# No tfvars required if using defaults; create one from the example if customizing
```

### Step 4 — Layer 4: Kubernetes Apps (< 1 min)

```bash
# Configure kubectl
cd gcp/clusters/shared
gcloud container clusters get-credentials $(terraform output -raw cluster_name) \
  --region $(terraform output -raw cluster_location) \
  --project your-gcp-project-id

# Apply namespace isolation CRDs and network policies
kubectl apply -f gcp/k8s-apps/dcf-crd/
```

---

## Variables Reference

### Layer 1 — gcp/network

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `name_prefix` | string | `"naas"` | No | Prefix for all resource names |
| `aviatrix_gcp_account_name` | string | — | **Yes** | GCP account name registered in the Aviatrix Controller |
| `gcp_project` | string | — | **Yes** | GCP project ID |
| `gcp_region` | string | `"us-central1"` | No | GCP region |
| `env` | string | `"prod"` | No | Environment tag value |
| `transit_cidr` | string | `"10.38.0.0/20"` | No | CIDR for the Aviatrix transit VPC |
| `shared_vpc_cidr` | string | `"10.40.0.0/16"` | No | Primary CIDR for the shared cluster VPC |
| `pod_cidr` | string | `"100.64.0.0/16"` | No | Secondary range for pod networking (alias IPs, RFC 6598) |
| `services_cidr` | string | `"172.40.0.0/20"` | No | Secondary range for Kubernetes services |
| `master_ipv4_cidr_block` | string | `"172.16.0.0/28"` | No | CIDR for GKE private master endpoint — must be /28 |
| `dns_private_zone_name` | string | `"gcp-naas.aviatrixdemo.local"` | No | Cloud DNS private zone domain name |
| `k8s_cluster_suffix` | string | `"shared-gke"` | No | Suffix appended to `name_prefix` for the cluster name |
| `k8s_cluster_id` | string | `""` | No | GKE cluster self-link for DCF SmartGroups (fill in after clusters/shared/ apply) |
| `team_namespaces` | list(string) | `["team-a","team-b","team-c"]` | No | Team namespace names (SmartGroup naming only — DCF rules are hardcoded) |
| `geo_block_countries` | list(string) | `["CN","RU","KP","IR"]` | No | ISO country codes to geo-block |
| `approved_web_domains` | list(string) | `["*.googleapis.com","ghcr.io",…]` | No | Domains permitted for namespace egress |
| `random_suffix` | bool | `true` | No | Append random hex to resource names |
| `manage_dcf` | bool | `false` | No | Set `true` only if this blueprint owns DCF lifecycle on the controller |

### Layer 2 — gcp/clusters/shared

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `release_channel` | string | `"REGULAR"` | No | GKE release channel: RAPID, REGULAR, or STABLE |
| `master_authorized_networks` | list(object) | `[{0.0.0.0/0, "All"}]` | No | CIDR blocks authorized to access the GKE master endpoint |

### Layer 3 — gcp/nodes/shared

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `node_pool_config` | object | `{min=2, max=6, initial=3, e2-standard-4, spot=true}` | No | GKE node pool configuration |
| `external_dns_chart_version` | string | `"1.19.0"` | No | Helm chart version for ExternalDNS |

---

## Outputs Reference

### gcp/network outputs

| Output | Description |
|---|---|
| `transit_gateway_name` | Aviatrix transit gateway name |
| `shared_network_name` | Shared cluster VPC network name |
| `shared_network_id` | Shared cluster VPC network ID (self-link) |
| `shared_network_self_link` | Shared cluster VPC self-link |
| `shared_gke_nodes_subnet_name` | GKE node subnet name |
| `shared_gke_nodes_subnet_cidr` | GKE node subnet CIDR |
| `shared_pod_range_name` | Pod secondary range name |
| `shared_services_range_name` | Services secondary range name |
| `shared_spoke_gateway_name` | Shared spoke gateway name |
| `shared_spoke_gateway_private_ip` | Spoke gateway private IP (SNAT target) |
| `dns_zone_name` | Cloud DNS zone resource name (for ExternalDNS) |
| `dns_zone_dns_name` | Cloud DNS zone domain name |
| `shared_cluster_name` | GKE cluster name |
| `gcp_region` | GCP region |
| `gcp_project` | GCP project ID |
| `pod_cidr` | Pod overlay CIDR |
| `services_cidr` | Services CIDR |
| `name_prefix` | Name prefix used for all resources |

### gcp/clusters/shared outputs

| Output | Description |
|---|---|
| `cluster_id` | GKE cluster self-link (input for `k8s_cluster_id` in network layer) |
| `cluster_name` | GKE cluster name |
| `cluster_location` | GKE cluster region |
| `cluster_endpoint` | GKE cluster API endpoint |
| `cluster_ca_certificate` | Base64 cluster CA cert |
| `external_dns_service_account_email` | Service account email for ExternalDNS Workload Identity |

gcp/nodes/shared exposes no outputs.

---

## Test Scenarios

### Scenario 1: Baseline namespace isolation

```bash
# Configure kubectl
cd gcp/clusters/shared
gcloud container clusters get-credentials $(terraform output -raw cluster_name) \
  --region $(terraform output -raw cluster_location) \
  --project your-gcp-project-id

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
# Expected: nginx response or TLS error (connection reaches the pod)

# Test: team-a -> team-c (DENY — DCF rule 50)
kubectl -n team-a exec netshoot -- curl -sk --max-time 5 https://team-c-svc.team-c.svc.cluster.local
# Expected: connection timeout

# Test: team-c -> team-b (DENY — DCF rule 55)
kubectl -n team-c exec netshoot -- curl -sk --max-time 5 https://team-b-svc.team-b.svc.cluster.local
# Expected: connection timeout
```

Expected results:

| Test | Expected | Enforced by |
|---|---|---|
| team-a → team-b TCP/443 | PASS | DCF rule 10 |
| team-a → team-c | BLOCKED | DCF rule 50 |
| team-c → team-a | BLOCKED | DCF rule 51 |
| team-b → team-c | BLOCKED | DCF rule 52 |
| team-c → team-b | BLOCKED | DCF rule 55 |

### Scenario 2: Monitoring namespace scrape access

```bash
kubectl create namespace monitoring

kubectl -n monitoring run netshoot --image=nicolaka/netshoot --command -- sleep infinity --restart=Never

# Test: monitoring -> team-a on TCP/9090 (PERMIT — DCF rule 5)
kubectl -n monitoring exec netshoot -- curl -sk --max-time 5 http://nginx.team-a.svc.cluster.local:9090
# Expected: connection attempt reaches the pod

# Test: monitoring -> team-a on TCP/80 (no PERMIT rule)
kubectl -n monitoring exec netshoot -- curl -sk --max-time 5 http://nginx.team-a.svc.cluster.local:80
# Expected: connection timeout
```

### Scenario 3: Egress to approved domains

```bash
# Test: team-a egress to an approved domain (PERMIT — DCF rule 60)
kubectl -n team-a exec netshoot -- curl -s --max-time 10 https://ghcr.io/v2/
# Expected: HTTP 200 or 401 (connection reaches the server)

# Test: team-a egress to an unapproved domain (DENY — no matching rule)
kubectl -n team-a exec netshoot -- curl -s --max-time 10 https://example.com
# Expected: connection timeout or TLS error
```

---

## Cleanup / Destroy

Destroy in reverse layer order.

```bash
# Step 1: Remove Kubernetes resources
kubectl delete -f gcp/k8s-apps/dcf-crd/
kubectl delete svc -A --field-selector spec.type=LoadBalancer
kubectl delete ingress --all -A
# Wait ~60 seconds for GCP to de-register LBs

# Step 2: Destroy Layer 3 — nodes
terraform -chdir=gcp/nodes/shared destroy -auto-approve

# Step 3: Destroy Layer 2 — cluster
terraform -chdir=gcp/clusters/shared destroy -auto-approve

# Step 4: Destroy Layer 1 — network
terraform -chdir=gcp/network destroy -var-file=terraform.tfvars -auto-approve
```

**Manual cleanup steps:**

- If ExternalDNS-managed Cloud DNS records are not removed before Step 2, they will be orphaned. List them with:
  ```bash
  gcloud dns record-sets list --zone=<zone-name> --project=your-gcp-project-id
  ```
- GKE node VMs create persistent disks automatically; confirm they are removed after Step 2:
  ```bash
  gcloud compute disks list --filter="labels.goog-gke-node=true" --project=your-gcp-project-id
  ```
- If `manage_dcf = true`, verify DCF and `k8s_config` are in the desired state after destroy.

**Verify cleanup:**

```bash
terraform -chdir=gcp/network state list
terraform -chdir=gcp/clusters/shared state list
terraform -chdir=gcp/nodes/shared state list

# Confirm no GKE clusters remain
gcloud container clusters list --project=your-gcp-project-id --region=us-central1
```

---

## Troubleshooting

**Namespace SmartGroups not enforcing**

DCF namespace enforcement requires the Aviatrix Controller to have read access to the GKE cluster via the GKE service account. The clusters/shared/ layer creates a service account with Workload Identity Federation for this purpose. In CoPilot, go to Security → Distributed Cloud Firewall → SmartGroups and confirm team namespaces appear as populated groups.

**`k8s_cluster_id` mismatch — pods not matching SmartGroups**

The `k8s_cluster_id` must be the GKE cluster self-link URL (format: `https://container.googleapis.com/v1/projects/{project}/locations/{location}/clusters/{name}`). After applying clusters/shared/, run `terraform output cluster_id` in that directory and paste the value into the network layer's `terraform.tfvars`. Re-apply the network layer.

**GKE node internet egress not routing through Aviatrix**

GKE nodes must carry the `avx-snat-noip` network tag for the Aviatrix spoke gateway to perform SNAT on their traffic. The nodes/shared/ layer sets this tag on the node pool. Verify with:
```bash
gcloud compute instances list \
  --filter="tags.items:avx-snat-noip" \
  --project=your-gcp-project-id
```
If missing, the node pool `tags` attribute may not have been applied. Re-apply nodes/shared/.

**Pods not getting 100.64.x.x addresses**

GKE VPC-native clusters use alias IP ranges. Verify the cluster was created with the correct secondary ranges:
```bash
gcloud container clusters describe <cluster-name> \
  --region us-central1 \
  --format="get(nodePools[0].config.secondaryBootDiskUpdateStrategy)"
kubectl get pods -A -o wide | grep -v 10\.40
```

**ExternalDNS fails to create Cloud DNS records**

ExternalDNS uses a Kubernetes service account annotated with Workload Identity Federation. Verify the service account binding:
```bash
kubectl describe sa external-dns -n kube-system
# Should show: iam.gke.io/gcp-service-account annotation
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns --tail=20
```

**GKE master endpoint unreachable from Terraform**

The GKE cluster is deployed with private master endpoint. If `master_authorized_networks` does not include the Terraform runner's IP, the provider cannot connect. Add your CIDR to `master_authorized_networks` in the clusters/shared/ tfvars:
```hcl
master_authorized_networks = [
  {
    cidr_block   = "your-ip/32"
    display_name = "Terraform runner"
  }
]
```

**`terraform destroy` hangs on `aviatrix_kubernetes_cluster`**

The Controller deregisters the cluster asynchronously. If destroy hangs beyond 5 minutes, check CoPilot → Infrastructure → Kubernetes to confirm the cluster was removed, then run `terraform state rm aviatrix_kubernetes_cluster.this` and retry.

---

## Tested With

| Component | Version |
|---|---|
| Aviatrix Controller | 7.2.x |
| Aviatrix Terraform Provider | ~> 8.2.0 |
| Terraform | >= 1.5 |
| Google Provider | ~> 6.0 |
| Kubernetes Provider | ~> 2.20 |
| Helm Provider | ~> 2.x |
| GKE Kubernetes version | 1.35 (REGULAR channel) |
| ExternalDNS chart | 1.19.0 |
