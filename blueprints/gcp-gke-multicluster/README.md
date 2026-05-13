# Multi-Cluster GKE Secured by the Aviatrix Cloud Native Security Fabric

This blueprint deploys a multi-cluster Kubernetes environment on Google Cloud, demonstrating the **Aviatrix Cloud Native Security Fabric (CNSF)** for Kubernetes — Distributed Cloud Firewall (DCF), workload segmentation, and Zero Trust enforcement across clusters. GCP counterpart to `aws-eks-multicluster` and `azure-aks-multicluster`.

> [!TIP]
> **Optimized for Claude Code** — Run `/deploy-blueprint` for AI-guided deployment with prerequisite checks and automated orchestration, or `/analyze-blueprint` for resource and cost details. [Get Claude Code](https://claude.ai/code)

> **Aviatrix Controller 9.0+ is required.** The blueprint relies on the controller programming a `0.0.0.0/0` route into each spoke VPC's routing table automatically; pre-9.0 controllers don't.

---

## Prerequisites

Before deploying this infrastructure, ensure you have the following prerequisites in place.

### Aviatrix Infrastructure

| Component | Requirement | Notes |
|-----------|-------------|-------|
| **Aviatrix Controller** | 9.0.10 or newer | Default-route propagation into the spoke VPC requires Controller 9.0. K8s SmartGroup membership requires CoPilot 9.0+. |
| **Aviatrix CoPilot** | Recommended | Required for DCF visualization, SmartGroup browsing, K8s cluster pod-IP membership, and FlowIQ flow inspection. |
| **Aviatrix GCP access account** | Onboarded in Controller | Default name in this blueprint: `Google`. The service account JSON loaded into the Controller needs `roles/compute.networkAdmin` (VPC + spoke gateway management) **plus** `roles/container.admin` or `roles/container.clusterAdmin` (GKE onboarding **and** the watch loop that reconciles DCF CRs into Controller-side SmartGroups — both need `container.clusters.getCredentials`). `roles/container.clusterViewer` alone is **not** sufficient: it satisfies onboarding but the watch loop silently fails to reconcile, so `FirewallPolicy`/`WebGroupPolicy` CRs you apply in Step 8 won't appear in CoPilot. See [Troubleshooting › GKE Cluster Shows "Onboarded: No"](#gke-cluster-shows-onboarded-no-in-copilot-or-dcf-crs-arent-reconciled) if symptoms appear. |

### Local Tools

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.5 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure provisioning |
| **`gcloud` CLI** | latest | [Install Guide](https://cloud.google.com/sdk/docs/install) | GCP authentication and the GKE auth plugin |
| **`kubectl`** | latest | [Install Guide](https://kubernetes.io/docs/tasks/tools/) | Kubernetes cluster interaction |
| **`gke-gcloud-auth-plugin`** | latest | `gcloud components install gke-gcloud-auth-plugin` | Required by `kubectl` for GKE token exchange |
| **Helm** | >= 3.x | [Install Guide](https://helm.sh/docs/intro/install/) | Used by Terraform's Helm provider for ExternalDNS + k8s-firewall |

### GCP Authentication

```bash
gcloud auth login
gcloud auth application-default login    # ADC for the Terraform google provider
gcloud config set project <YOUR_PROJECT_ID>
```

The `aviatrix_gcp_account_name` referenced by `network/terraform.tfvars` must already be onboarded in the Aviatrix Controller and bound to a service account in this same GCP project.

### Required GCP APIs

Enable these once per project:

```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  dns.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com
```

The `network/main.tf` also enables them as Terraform-managed `google_project_service` resources, but enabling them up front avoids first-apply timing races.

### GCP Project Quotas

This blueprint deploys 4 Aviatrix gateways, 4 GKE nodes, and 1 Apache test VM in a single region. Default project quotas in `us-central1` are usually enough; the typical pinch points:

| Quota | Need | Default |
|-------|------|---------|
| `CPUS` (per region) | ~13 vCPU (4 × n1-standard-1 + 4 × e2-standard-2 + 1 × e2-small) | 24+ |
| `IN_USE_ADDRESSES` (per region) | ~6 (gateway public IPs + 2 reserved global IPs for ALBs) | 8+ |
| `BACKEND_SERVICES` (per project) | 2 (one per GKE Gateway) | 75 |
| `URL_MAPS` (per project) | 2 (one per GKE Gateway) | 25 |

Check current usage:
```bash
gcloud compute regions describe us-central1 \
  --project=<YOUR_PROJECT_ID> \
  --flatten="quotas[]" \
  --format="table(quotas.metric,quotas.usage,quotas.limit)" \
  | grep -E "^(CPUS|IN_USE_ADDRESSES)\b"
```

If you need an increase, file the request via Console → IAM & Admin → Quotas. Up to ~50 vCPUs is generally auto-approved.

---

## Architecture Overview

```
                              Internet
                                 │
                  ┌──────────────┴──────────────┐
                  ▼                              ▼
       Frontend GKE Gateway              Backend GKE Gateway
     (Global External ALB)              (Global External ALB)
       reserved global IPv4               reserved global IPv4
                  │                              │
       ┌──────────▼──────────┐         ┌──────────▼──────────┐
       │ Frontend VPC         │         │ Backend VPC          │
       │ 10.10.0.0/20         │         │ 10.20.0.0/20         │
       │                      │         │                      │
       │ GKE frontend         │         │ GKE backend          │
       │ Dataplane V2 (eBPF)  │         │ Dataplane V2 (eBPF)  │
       │ pods 100.64.0.0/16   │         │ pods 100.64.0.0/16   │
       │                      │         │                      │
       │ Aviatrix Spoke GW    │         │ Aviatrix Spoke GW    │
       │ customized_snat      │         │ customized_snat      │
       │  100.64/16 → GW IP   │         │  100.64/16 → GW IP   │
       └──────────┬───────────┘         └──────────┬───────────┘
                  │   Aviatrix Transit Fabric      │
                  └───────────────┬────────────────┘
                                  │
                       ┌──────────▼──────────┐
                       │ Aviatrix Transit    │
                       │ Transit VPC         │
                       │ 10.2.0.0/24         │
                       └──────────┬──────────┘
                                  │
                       ┌──────────▼──────────┐
                       │ DB Spoke VPC        │
                       │ 10.5.0.0/22         │
                       │ Apache test VM      │
                       │ db.gcp.aviatrixdemo │
                       │     .local          │
                       └─────────────────────┘
```

### Why GKE Gateway API Instead of an Internal NGINX Layer

The AKS variant of this blueprint uses **Azure Application Gateway → internal NGINX** because Azure's public Standard Load Balancer combined with a `0/0 → spoke GW` UDR causes asymmetric routing: return traffic exits through the UDR and arrives at the client from the Aviatrix GW IP rather than the LB IP, so TCP drops it.

**GCP doesn't have that trap with Google-managed L7 load balancers.** Return traffic for a Global External ALB flows back through Google's load balancer plane, not through the VPC's `0/0` route. So this blueprint uses **GKE Gateway API** (`gatewayClassName: gke-l7-global-external-managed`), which provisions a native Google Global External Application Load Balancer, attaches Gatus Services via container-native NEGs, and avoids the NGINX hop entirely.

### Traffic Flow (Internet → Gatus)

```
Internet client
  → Reserved Global IPv4 :80
  → Google Frontend (GFE) → Global External ALB
  → Container-native NEG → Gatus pod :8080
  ← response back through Google's LB plane
  ← GFE → client
```

The Aviatrix `0/0 → spoke GW` route at priority 991 in the spoke VPC affects **VM-originated** egress (including pod-sourced traffic that's not response traffic for the ALB). Response traffic for ALB flows uses Google's LB plane and does not traverse the priority-991 route, so there is no asymmetric routing.

### Pod Networking (GKE Dataplane V2)

Both clusters run **GKE Dataplane V2** (Cilium-based eBPF, replaces kube-proxy; provides NetworkPolicy enforcement out of the box). Pod IPs come from the alias secondary range `100.64.0.0/16` — **the same in both clusters, fully overlapping by design.**

Aviatrix spoke gateways SNAT pod source IPs to the spoke GW's private IP via `customized_snat` policies before forwarding to transit, allowing the overlapping pod CIDRs to coexist without routing conflicts. Each cluster's `default_snat_status.disabled = true` ensures pod IPs reach the spoke GW unmasqueraded — equivalent to `enableIPv4Masquerade=false` in the AKS variant.

### Pod Traffic Flow (Cross-Cluster)

```
Frontend pod (100.64.x.x)
  → frontend-nodes subnet (10.10.0.0/22)
  → 0.0.0.0/0 priority-991 → Frontend Aviatrix Spoke GW (10.10.4.2)
  → CONDUIT_SNAT iptables: src 100.64.0.0/16 → SNAT to 10.10.4.2
  → IPsec tunnel to Aviatrix Transit GW
  → IPsec tunnel to Backend Spoke GW
  → Backend GKE service / pod IP (10.20.x.x or 100.64.x.x)
  ← reverse path symmetric (SNAT preserves conntrack)
```

---

## Directory Structure

```
gcp-gke-multicluster/
├── network/                       # Layer 1: Network foundation
│   ├── main.tf                    # Transit + 3 spoke GWs + customized_snat + DB VM + global IPs + DNS
│   ├── dcf.tf                     # SmartGroups, WebGroups, ruleset (priorities 10-25)
│   ├── dcf-k8s.tf                 # K8s-typed SmartGroups (gated by enable_k8s_smartgroup_demo)
│   ├── variables.tf
│   ├── outputs.tf                 # VPC IDs, subnet names, gateway IPs, DCF UUIDs
│   └── modules/
│       ├── gke-vpc/               # VPC + node subnet (with pod/service alias ranges)
│       │                          #   + Aviatrix GW subnet + proxy-only subnet + firewall rules
│       └── linux-vm/              # Ubuntu Apache test VM
│
├── clusters/
│   ├── frontend/                  # Layer 2: Frontend GKE control plane + node pool + GSAs
│   │   ├── main.tf                # GKE cluster, node pool, ExternalDNS GSA + WIF binding
│   │   ├── onboarding.tf          # aviatrix_kubernetes_cluster registration
│   │   ├── data.tf                # Read network state
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── backend/                   # Layer 2: Backend GKE control plane (parallel)
│
├── nodes/
│   ├── frontend/                  # Layer 3: Helm add-ons
│   │   ├── main.tf                # google + kubernetes + helm provider blocks
│   │   ├── helm.tf                # ExternalDNS (Cloud DNS) + Aviatrix k8s-firewall
│   │   ├── data.tf                # Read network + cluster state
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── backend/                   # Layer 3: Backend Helm add-ons (parallel)
│
└── k8s-apps/                      # Layer 4: Kubernetes manifests (kubectl apply)
    ├── frontend/gatus.yaml        # Gatus + Service + Gateway + HTTPRoute
    ├── backend/gatus.yaml
    └── dcf-crd/                   # DCF Kubernetes CRD policy examples
        ├── firewallpolicy-infosec.yaml
        └── webgrouppolicy-dev.yaml
```

### State Dependencies

```
network/terraform.tfstate
    │
    ├── clusters/frontend/terraform.tfstate
    │       │
    │       └── nodes/frontend/terraform.tfstate
    │
    └── clusters/backend/terraform.tfstate
            │
            └── nodes/backend/terraform.tfstate
```

Each layer reads the previous layer's state via `data "terraform_remote_state" "local"`. **All state is local — no remote backend.** All blueprints in this repository follow the same convention.

---

## Complete Deployment Guide

> **Note:** Complete all items in the [Prerequisites](#prerequisites) section before proceeding.
>
> **Total deploy time:** ~40-55 minutes wall-clock when running same-level layers in parallel:
> - network: ~10-15 min (most time is Aviatrix gateway creation + IPsec tunnel setup)
> - clusters: ~10-15 min parallel (GKE control plane creation)
> - nodes: ~2-3 min parallel (Helm chart installation)
> - k8s-apps: ~2-3 min (kubectl apply + pod readiness)

### Step 0: Get the Source

```bash
git clone https://github.com/AviatrixSystems/aviatrix-blueprints.git
cd aviatrix-blueprints/blueprints/gcp-gke-multicluster
```

All subsequent `cd` paths are relative to `blueprints/gcp-gke-multicluster/`.

### Step 1: Set Environment Variables

```bash
# Aviatrix Controller credentials (always required)
export AVIATRIX_CONTROLLER_IP="<controller-ip>"
export AVIATRIX_USERNAME="<username>"
export AVIATRIX_PASSWORD="<password>"
```

**GCP authentication** — application default credentials are required for the Terraform `google` provider:

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project <YOUR_PROJECT_ID>

# Verify
gcloud auth list
gcloud config get project
```

> [!IMPORTANT]
> When the cluster layers run with `enable_aviatrix_onboarding = true` (default), the Aviatrix Controller calls each GKE API server directly after fetching the kubeconfig from the GKE container API. The controller's public egress IP must be in the cluster's `master_authorized_networks`:
> - **If you set `master_authorized_cidr_blocks = ["0.0.0.0/0"]`** (the example default): no extra config needed — `0.0.0.0/0` already covers the controller.
> - **If you restrict `master_authorized_cidr_blocks`** to your own IP: also set `aviatrix_controller_public_ip` in `clusters/*/terraform.tfvars` so the controller's IP gets appended automatically. For SaaS / Cloud Fabric controllers this is the same value as `AVIATRIX_CONTROLLER_IP`; for self-hosted controllers behind NAT, use the controller's public egress IP (not its management IP).

### Step 2: Deploy Network Infrastructure

The network layer creates the Aviatrix transit/spoke topology, three GCP VPCs with subnets and secondary alias ranges, the GCP private DNS zone, the DB test VM, and the DCF policy ruleset.

```bash
cd network/

# Initialize Terraform
terraform init -upgrade

# Create your variable file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set at minimum:
#   name_prefix                 (e.g., "gke-demo")
#   aviatrix_gcp_account_name   (your GCP account name in Aviatrix Controller, e.g., "Google")
#   gcp_project_id              (your GCP project ID)
#   gcp_region                  (default: us-central1)
#   gcp_zone                    (default: us-central1-a)
vim terraform.tfvars

# Deploy network infrastructure (~10-15 minutes)
terraform apply
```

> [!TIP]
> If `terraform apply` fails partway through with a transient error, simply re-run `terraform apply`. Terraform picks up where it left off and the retry normally succeeds. This is not a configuration bug. Common transients on this blueprint:
>
> - **Aviatrix Controller** — `connection reset by peer` / `502 Bad Gateway` (most often during `aviatrix_spoke_transit_attachment` or `aviatrix_gateway_snat`).
> - **GCP** — `Error waiting for instance to create: Internal error.` on `module.db_vm.google_compute_instance.this`.

**What's created:**

- Aviatrix Transit Gateway (`10.2.0.0/24`, `excluded_advertised_spoke_routes = "100.64.0.0/16"` to keep pod CIDRs out of BGP)
- Frontend VPC (`10.10.0.0/20`) with Aviatrix spoke gateway and `customized_snat` policies
- Backend VPC (`10.20.0.0/20`) with Aviatrix spoke gateway and `customized_snat` policies
- DB spoke VPC (`10.5.0.0/22`) with Linux test VM (Apache, listens on port 80)
- Each spoke VPC has subnets: nodes (`10.x.0.0/22`, with `100.64.0.0/16` pod and `172.16.0.0/20` service secondary ranges), Aviatrix GW (`10.x.4.0/28`), proxy-only (`10.x.5.0/24`)
- GCP Private DNS zone (`gcp.aviatrixdemo.local.`) bound to all three spoke VPCs
- Static A record `db.gcp.aviatrixdemo.local` → DB VM IP
- 2 reserved global external IPv4 addresses (one per cluster's GKE Gateway)
- DCF SmartGroups, WebGroups, and policy ruleset (priorities 10-25; see [DCF Rules](#dcf-rules))

### Step 3: Deploy Frontend GKE Cluster

The cluster layer creates the GKE control plane (Dataplane V2 / Cilium eBPF), primary node pool, two service accounts (node SA, ExternalDNS GSA with Workload Identity Federation binding), and the `aviatrix_kubernetes_cluster` registration.

```bash
cd ../clusters/frontend/

# Initialize Terraform
terraform init

# (Optional) Override defaults
cp terraform.tfvars.example terraform.tfvars
# Inputs you may want to set:
#   master_authorized_cidr_blocks  (default ["0.0.0.0/0"]; restrict to your IP for prod)
#   enable_aviatrix_onboarding     (default true — registers cluster with Controller)
#   aviatrix_controller_public_ip  (required only when master_authorized_cidr_blocks is restrictive)
vim terraform.tfvars   # only needed if you customized any of the above

# Deploy cluster (~10-15 minutes)
terraform apply
```

> [!TIP]
> GKE control-plane creation occasionally fails fast (~30-60s) with `Error waiting for creating GKE cluster: Failed to create cluster` (a generic GCP `INTERNAL` error). The cluster is left in `STATUS=ERROR`; re-run `terraform apply` and Terraform will plan a destroy of the ERROR cluster and recreate it — the retry typically succeeds. No manual `gcloud container clusters delete` is required. Same advice applies to Step 4.

**What's created:**

- GKE cluster (`gke-demo-frontend`) — zonal, Dataplane V2 (Cilium eBPF), private nodes, public master endpoint with allowlist, Gateway API CRDs (channel STANDARD), Workload Identity (`<project>.svc.id.goog`)
- Primary node pool (`primary`, default 2 × `e2-standard-2`, autoscale 1-3)
- Node service account (`<cluster>-node-sa`) with logging/monitoring/artifact-reader roles
- ExternalDNS service account (`<cluster>-edns`) with `roles/dns.admin` + a Workload Identity binding to `kube-system/external-dns`
- `aviatrix_kubernetes_cluster` registration with the Aviatrix Controller (when `enable_aviatrix_onboarding = true`)

### Step 4: Deploy Backend GKE Cluster (Parallel with Step 3)

```bash
cd ../backend/

# Initialize Terraform
terraform init

# Same tfvars pattern as frontend
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars   # only if customizing

# Deploy cluster (~10-15 minutes)
terraform apply
```

**What's created:** Same as the frontend cluster, scoped to the backend VPC.

Steps 3 and 4 can run in parallel in separate terminals. The two clusters have no Terraform-level dependency on each other.

### Step 5: Deploy Frontend Helm Add-ons

The node layer installs ExternalDNS (Cloud DNS provider via Workload Identity Federation) and the Aviatrix `k8s-firewall` Helm chart (DCF CRDs).

```bash
cd ../../nodes/frontend/

# Initialize Terraform
terraform init

# Deploy Helm charts (~2-3 minutes)
terraform apply
```

**What's created:**

- ExternalDNS Helm release in `kube-system` (creates Private DNS A records for annotated Services and Gateways)
- Aviatrix `k8s-firewall` Helm release (installs the `FirewallPolicy` and `WebGroupPolicy` CRDs plus a ClusterRole + ClusterRoleBinding granting the `avx-controller` ClusterRole read access on `pods/services/namespaces/endpointslices` and update permission on the DCF CRDs — **the chart contains no in-cluster controller pod**; the Aviatrix Controller itself watches the cluster API and reconciles CRs into Controller-side SmartGroups + policy-list rules)

### Step 6: Deploy Backend Helm Add-ons (Parallel with Step 5)

```bash
cd ../backend/

# Initialize Terraform
terraform init

# Deploy Helm charts (~2-3 minutes)
terraform apply
```

Steps 5 and 6 can run in parallel in separate terminals.

### Step 7: Configure kubectl for Both Clusters

`gcloud container clusters get-credentials` creates a kubectl context with the auto-generated name `gke_<project>_<zone>_<cluster>`. We use that name directly in the examples below; if you'd rather use a short alias, see the [Optional: Rename kubectl Contexts](#optional-rename-kubectl-contexts) section.

```bash
# Pull credentials for both clusters
gcloud container clusters get-credentials gke-demo-frontend \
  --zone us-central1-a --project <YOUR_PROJECT_ID>

gcloud container clusters get-credentials gke-demo-backend \
  --zone us-central1-a --project <YOUR_PROJECT_ID>

# Verify both clusters
PROJECT=$(gcloud config get project)
kubectl --context=gke_${PROJECT}_us-central1-a_gke-demo-frontend get nodes
kubectl --context=gke_${PROJECT}_us-central1-a_gke-demo-backend get nodes
```

**Expected output (one row per node, default 2):**
```
NAME                                          STATUS   ROLES    AGE   VERSION
gke-gke-demo-frontend-primary-8ead9b6a-hb76   Ready    <none>   12m   v1.33.x-gke.xxx
gke-gke-demo-frontend-primary-8ead9b6a-nnc9   Ready    <none>   12m   v1.33.x-gke.xxx
```

#### Rename kubectl Contexts

The auto-generated names get unwieldy, and **the rest of this guide assumes the short aliases below.** Step 8 and every Test Scenario use `--context=frontend` / `--context=backend`; without the rename, those commands fail with `context not found`. Shorten:

```bash
PROJECT=$(gcloud config get project)
kubectl config rename-context gke_${PROJECT}_us-central1-a_gke-demo-frontend frontend
kubectl config rename-context gke_${PROJECT}_us-central1-a_gke-demo-backend  backend

# All subsequent kubectl commands use --context=frontend or --context=backend
kubectl --context=frontend get nodes
```

The remainder of this guide uses `--context=frontend` and `--context=backend` for brevity.

### Step 8: Deploy Gatus Monitoring Dashboards

Gatus is a YAML-driven uptime monitor. Each cluster runs its own dashboard that monitors:
- Cross-cluster east-west via Aviatrix transit (`backend.gcp.aviatrixdemo.local:8080` from frontend, and vice-versa)
- The DB VM via private DNS (`db.gcp.aviatrixdemo.local`)
- DCF-allowed external endpoints (kubernetes.io, github.com/AviatrixSystems, npmjs.org)
- DCF-blocked threat endpoints (geo-blocked country, ThreatGuard feed IP)

Apply the manifests in this order — Gatus creates the `gatus` namespace, and the DCF CRD examples live in that namespace + a separate `dev` namespace:

```bash
# 1. Gatus dashboards (creates the gatus namespace + Gateway + HTTPRoute)
kubectl --context=frontend apply -f k8s-apps/frontend/gatus.yaml
kubectl --context=backend  apply -f k8s-apps/backend/gatus.yaml

# 2. Create the dev namespace (used by webgrouppolicy-dev.yaml)
kubectl --context=frontend create namespace dev --dry-run=client -o yaml | kubectl --context=frontend apply -f -
kubectl --context=backend  create namespace dev --dry-run=client -o yaml | kubectl --context=backend  apply -f -

# 3. DCF CRD examples (FirewallPolicy in gatus ns, WebGroupPolicy in dev ns)
kubectl --context=frontend apply -f k8s-apps/dcf-crd/
kubectl --context=backend  apply -f k8s-apps/dcf-crd/

# Verify Gatus pods are running
kubectl --context=frontend get pods -n gatus
kubectl --context=backend  get pods -n gatus
```

**Expected output:**
```
NAME                        READY   STATUS    RESTARTS   AGE
frontend-755f8587fb-m5f4m   1/1     Running   0          60s
frontend-755f8587fb-zjczn   1/1     Running   0          60s
```

The first time the GKE Gateway resource provisions a Global External ALB it can take 3-5 minutes. Watch progress:
```bash
kubectl --context=frontend get gateway -n gatus -w
# Wait for PROGRAMMED=True and ADDRESS populated
```

#### Get the Public ALB IPs

> [!IMPORTANT]
> Always read the ALB IP from the live Gateway, **not** from the `network/` Terraform output. The `network/` layer pre-reserves global addresses and the Gatus manifest annotates them via `networking.gke.io/addresses`, but on some current GKE versions the `gke-l7-global-external-managed` controller does **not** honor short-name annotations and mints a fresh address instead — leaving the reserved IPs in `STATUS=RESERVED` (unused) while Gatus serves on a different IP. Reading from `kubectl get gateway` always returns the live address regardless of which path is in effect.

```bash
FRONTEND_IP=$(kubectl --context=frontend get gateway frontend-public -n gatus \
  -o jsonpath='{.status.addresses[0].value}')
BACKEND_IP=$(kubectl --context=backend  get gateway backend-public  -n gatus \
  -o jsonpath='{.status.addresses[0].value}')
echo "Frontend ALB: $FRONTEND_IP"
echo "Backend  ALB: $BACKEND_IP"

# Optional: verify whether the reserved IP got bound (success path = STATUS=IN_USE)
gcloud compute addresses list --global --filter="name~gke-demo" \
  --format="table(name,address,status)"
```

Open `http://$FRONTEND_IP/` and `http://$BACKEND_IP/` in a browser. Each shows a Gatus dashboard.

---

## Test Scenarios

### Scenario 1: Internet Access via GKE Gateway (Public ALB)

Verify the path GFE → Global External ALB → container-native NEG → Gatus pod is working end-to-end.

```bash
# Read the live ALB IP from the Gateway resource — the network/ tf output returns the
# *reserved* global IP, which the GKE Gateway controller may or may not have bound to.
FRONTEND_IP=$(kubectl --context=frontend get gateway frontend-public -n gatus \
  -o jsonpath='{.status.addresses[0].value}')
BACKEND_IP=$(kubectl --context=backend  get gateway backend-public  -n gatus \
  -o jsonpath='{.status.addresses[0].value}')

curl -s -o /dev/null -w "%{http_code}\n" http://$FRONTEND_IP/
# Expected: 200

curl -s -o /dev/null -w "%{http_code}\n" http://$BACKEND_IP/
# Expected: 200
```

### Scenario 2: Pod-to-Internet Egress (Aviatrix `customized_snat`)

A frontend pod's traffic to the internet should appear sourced from the **frontend spoke gateway's public IP** (not the pod IP, not the node IP). This proves the data path:
1. Pod → priority-991 default route → Spoke GW
2. Spoke GW iptables `CONDUIT_SNAT` → SNAT pod-CIDR src → spoke GW private IP
3. Spoke GW eth0 → Internet Gateway → 1:1 NAT to spoke GW public IP

```bash
# Spawn a debug pod with curl/dig/tcpdump
kubectl --context=frontend run debug --image=nicolaka/netshoot:latest \
  --namespace=gatus --restart=Never --command -- sleep 600
kubectl --context=frontend wait --for=condition=ready pod/debug -n gatus --timeout=60s

# Pod IP (should be 100.64.x.x)
kubectl --context=frontend get pod debug -n gatus -o jsonpath='{.status.podIP}'; echo

# Internet egress source IP
SPOKE_PUB=$(cd network/ && terraform output -raw frontend_spoke_gateway_public_ip)
echo "Frontend spoke GW public IP: $SPOKE_PUB"

kubectl --context=frontend exec -n gatus debug -- curl -sm 10 https://ifconfig.io
# Expected: $SPOKE_PUB (the spoke GW's public IP)

# HTTP test
kubectl --context=frontend exec -n gatus debug -- curl -sm 10 -o /dev/null \
  -w "HTTP %{http_code} in %{time_total}s\n" https://kubernetes.io
# Expected: HTTP 200 in <1s
```

### Scenario 3: East-West Cross-Cluster (via Aviatrix Transit)

Frontend pod hits backend service over the private DNS name. Both clusters use overlapping `100.64.0.0/16` pod CIDRs — Aviatrix `customized_snat` makes that invisible east-west.

```bash
# Cross-cluster: frontend pod → backend Gatus service via transit
kubectl --context=frontend exec -n gatus debug -- \
  curl -sm 8 -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" \
  http://backend.gcp.aviatrixdemo.local:8080
# Expected: HTTP 200 in <100ms

# Frontend pod → DB VM (Apache) via transit
kubectl --context=frontend exec -n gatus debug -- \
  curl -sm 8 -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" \
  http://db.gcp.aviatrixdemo.local
# Expected: HTTP 200 in <100ms
```

The **Internal Services** group on the Gatus dashboard exercises the same cross-cluster path continuously.

### Scenario 4: DCF Egress Allow (Customized SNAT + WebGroup Match)

The DCF ruleset allows specific external destinations via WebGroups. Confirmed-allowed:
- `kubernetes.io` (`*-wg-kubernetes-io`)
- `github.com/AviatrixSystems/*` (`*-wg-github-aviatrix`)
- `registry.npmjs.org` (`*-wg-npm-registry`)
- Docker Hub (`*-wg-docker-hub`)
- Required GCP services — `*.googleapis.com`, `*.gcr.io`, `*.pkg.dev` (`*-wg-gcp-required`)

```bash
# All should return HTTP 200
for url in https://kubernetes.io https://github.com/AviatrixSystems/terraform-provider-aviatrix https://registry.npmjs.org; do
  CODE=$(kubectl --context=frontend exec -n gatus debug -- curl -sm 8 -o /dev/null -w "%{http_code}" "$url")
  echo "$url → $CODE"
done
```

The **Egress** group on the Gatus dashboard runs the same checks every 60 seconds.

### Scenario 5: DCF Threat Blocking (GeoBlock + ThreatIQ)

The Gatus dashboard includes two threat endpoints **expected to be blocked**:
- A geo-blocked destination (configurable in `network/dcf.tf`'s `geo_blocked` SmartGroup — default Iran/Russia/North Korea/China)
- A ThreatGuard-feed IP

These show as **red/down** in the Gatus dashboard, which is the correct behavior. If both show green, your ThreatGuard feed may not be active or the IP rolled out of the feed (Emerging Threats Open's `compromised-ips.txt` rotates roughly daily). To refresh:

```bash
# Pick a current IP from the feed
curl -s https://rules.emergingthreats.net/blockrules/compromised-ips.txt | grep -vE '^(#|$)' | head -1

# Update the IP in both gatus.yaml files
vim k8s-apps/frontend/gatus.yaml   # find "Threat Feed - Malicious IP"
vim k8s-apps/backend/gatus.yaml

# Re-apply
kubectl --context=frontend apply -f k8s-apps/frontend/gatus.yaml
kubectl --context=backend  apply -f k8s-apps/backend/gatus.yaml
```

### Scenario 6: K8s-Typed SmartGroup Membership

The K8s-typed SmartGroups created in `network/dcf-k8s.tf` populate dynamically from the cluster API once onboarding succeeds. **CoPilot is the canonical place to verify this** — the Controller API confirms cluster *registration* but doesn't expose resolved pod IPs.

```bash
# Confirm both clusters are registered with use_csp_credentials=true
CID=$(curl -sk -X POST "https://${AVIATRIX_CONTROLLER_IP}/v1/api" \
  -d "action=login&username=${AVIATRIX_USERNAME}&password=${AVIATRIX_PASSWORD}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['CID'])")

curl -sk -H "Authorization: cid ${CID}" \
  "https://${AVIATRIX_CONTROLLER_IP}/v2.5/api/k8s/clusters" | python3 -m json.tool
# Expected: both gke-demo-frontend and gke-demo-backend listed.
```

In **CoPilot**:
- Cloud Workloads → Kubernetes Clusters: both clusters show **Onboarded: Yes** with namespace and pod counts populated. First-time sync after onboarding can take ~10 minutes.
- Security → SmartGroups → `gke-demo-sg-frontend-gatus-ns` → Members tab: lists the gatus pod IPs (100.64.x.x range, dynamically resolved).

The priority-50 DCF rule "Frontend Gatus to Backend Gatus k8s ns selector" (in `network/dcf.tf`, gated by `enable_k8s_smartgroup_demo`) references these K8s-typed SmartGroups. While membership is empty the rule is a no-op, but the lower-priority VPC-based rules (priority 14/15) still permit the cross-cluster gatus traffic, so dashboard checks remain green.

### Scenario 7: DCF CRD-Based Policies (Kubernetes-Native)

The `k8s-apps/dcf-crd/` manifests demonstrate Kubernetes-native DCF policy management — pods labeled `app=infosec` get an additional FirewallPolicy, pods in the `dev` namespace get a broader WebGroupPolicy.

```bash
# Already applied in Step 8 — verify they're accepted
kubectl --context=frontend get firewallpolicies -n gatus
kubectl --context=frontend get webgrouppolicies -n dev

# Expected:
# firewallpolicy.networking.aviatrix.com/infosec-egress
# webgrouppolicy.networking.aviatrix.com/dev-external-apis
```

The Aviatrix `k8s-firewall` controller watches these CRDs and creates corresponding Controller-side SmartGroups + policy lists. Verify in CoPilot → Security → SmartGroups: you should see entries with the prefix `firewallpolicysource-` and `webgrouppolicy-target-`.

### Scenario 8: Private DNS Resolution

ExternalDNS creates Cloud DNS records for annotated Services and Gateways:

```bash
gcloud dns record-sets list \
  --project=<YOUR_PROJECT_ID> \
  --zone=gke-demo-private-zone \
  --format="table(name,type,rrdatas.list():label=VALUES)"
```

**Expected records:**

| FQDN | Resolves to | Source |
|---|---|---|
| `frontend.gcp.aviatrixdemo.local` | frontend cluster's internal LB IP (10.10.x.x) | Service `gatus/frontend` |
| `backend.gcp.aviatrixdemo.local` | backend cluster's internal LB IP (10.20.x.x) | Service `gatus/backend` |
| `db.gcp.aviatrixdemo.local` | DB VM IP (10.5.0.2) | Static record from Terraform |

Verify resolution from inside a pod:
```bash
kubectl --context=frontend exec -n gatus debug -- nslookup backend.gcp.aviatrixdemo.local
# Expected: 10.20.0.5 (or whatever the backend service-LB IP is)
```

---

## How It Works

### GKE Dataplane V2 + `default_snat_status.disabled`

Both clusters use **Dataplane V2** (Cilium-based eBPF), which replaces kube-proxy. NetworkPolicy enforcement is enabled by default, and pod IPs come from the alias secondary range `100.64.0.0/16`.

By default GKE applies node-level IP masquerade for pod traffic — pod source IPs are SNAT'd to the node IP before leaving the node. This blueprint disables that with `default_snat_status.disabled = true`, so pod IPs reach the Aviatrix spoke gateway **unmasqueraded**. The spoke GW then SNATs pod source IPs to its own private IP at the iptables `CONDUIT_SNAT` chain.

This two-step is necessary because:
- DCF SmartGroup matching needs to see the **original pod IP** at the spoke (for K8s-typed SmartGroup membership and for hostname-based policy lookups).
- The transit fabric needs SNATed packets so overlapping pod CIDRs (both clusters use `100.64.0.0/16`) don't collide.

### Aviatrix `customized_snat` on GCP

This blueprint sets `aviatrix_gateway_snat` resources on each spoke gateway with `snat_mode = "customized_snat"` and three policies per spoke:

```hcl
# Pod CIDR → all destinations via transit (cross-cluster east-west)
snat_policy {
  src_cidr   = var.frontend_pods_cidr           # 100.64.0.0/16
  dst_cidr   = "0.0.0.0/0"
  interface  = ""
  connection = module.gcp_transit.transit_gateway.gw_name
  snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
}

# Pod CIDR → internet via eth0
snat_policy {
  src_cidr  = var.frontend_pods_cidr            # 100.64.0.0/16
  dst_cidr  = "0.0.0.0/0"
  interface = "eth0"
  snat_ips  = module.frontend_spoke.spoke_gateway.private_ip
}

# Node subnet → internet via eth0 (covers GKE node-level traffic)
snat_policy {
  src_cidr  = var.frontend_nodes_cidr           # 10.10.0.0/22
  dst_cidr  = "0.0.0.0/0"
  interface = "eth0"
  snat_ips  = module.frontend_spoke.spoke_gateway.private_ip
}
```

These render on the spoke GW as iptables rules in the `CONDUIT_SNAT` chain:

```
Chain CONDUIT_SNAT (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 ACCEPT     0    --  *      *       0.0.0.0/0   0.0.0.0/0   policy match dir out pol ipsec
   12   720 SNAT       0    --  *      *       100.64.0.0/16 0.0.0.0/0  dst-group 0x1 to:10.10.4.2
   33  1884 SNAT       0    --  *      eth0    100.64.0.0/16 0.0.0.0/0   to:10.10.4.2
    0     0 SNAT       0    --  *      eth0    10.10.0.0/22  0.0.0.0/0   to:10.10.4.2
```

The first rule (IPsec policy match → ACCEPT) is an internal Aviatrix bypass for transit IPsec packets that should **not** be SNATed twice. The transit-direction SNAT rule (rule 2) uses `dst-group 0x1` which is the controller's representation of "any destination reachable through transit."

### Why Not `single_ip_snat`?

The `single_ip_snat = true` flag on the spoke gateway is the simplest pattern, and it works fine for north-south internet egress on GCP. **It does not, however, SNAT east-west traffic through the IPsec transit tunnel.** With overlapping pod CIDRs (both clusters use `100.64.0.0/16`), un-SNAT'd pod IPs arriving at the destination spoke route into the wrong cluster's pod range and replies fail. `customized_snat` with explicit `connection =` policies is the only way to SNAT both directions on GCP without triggering the AVXERR-NAT-0029 conflict that the AKS variant sees.

### Controller-Managed `0.0.0.0/0` Default Route (Priority 991)

Aviatrix Controller 9.0+ programs a `0.0.0.0/0 → spoke-GW-instance` route at priority 991 in each spoke VPC's route table (per **AVX-71737** — the route is **untagged** so it applies to GKE-managed nodes that don't carry the `avx-snat-noip` instance tag). You can verify:

```bash
gcloud compute routes list \
  --project=<YOUR_PROJECT_ID> \
  --filter="network:gke-demo-frontend-vpc AND priority=991" \
  --format="table(name,priority,destRange,nextHopInstance.basename(),tags.list())"

# Expected:
# NAME                                  PRIORITY  DEST_RANGE  NEXT_HOP_INSTANCE        TAGS
# avx-958e25524fb245ea8793514d423feb6e  991       0.0.0.0/0   gke-demo-frontend-spoke
```

There's also a priority-500 `0.0.0.0/0 → IGW` route **tagged** with `avx-<vpc-name>-vpc-gbl` — that's the egress route for the Aviatrix gateway VM itself. The 991 untagged route applies to all other VMs (GKE nodes, pods).

### Reserved Global IPv4 Addresses for GKE Gateways

The `network/` layer pre-reserves two `EXTERNAL` global addresses (one per cluster). The Gatus Gateway resource in each cluster references them by name via `networking.gke.io/addresses`. Reserving them in `network/` keeps DNS and downstream wiring stable across `nodes/` layer rebuilds — destroying and re-applying nodes won't change the public IP.

---

## DCF Rules

The `network/dcf.tf` ruleset has these policies (priorities 10-25). Lower number = evaluated first.

| Priority | Name | Source | Destination | Action |
|---:|---|---|---|---|
| 10 | Block GeoBlocked Countries | All GKE | Geo-blocked countries | DENY |
| 11 | Block Threat Intel IPs | All GKE | ThreatGuard feed | DENY |
| 14 | Frontend to Database | Frontend VPC | DB VPC | PERMIT |
| 15 | Backend to Database | Backend VPC | DB VPC | PERMIT |
| 16 | Frontend to Backend Services | Frontend VPC | Backend VPC | PERMIT |
| 17 | Backend to Frontend Services | Backend VPC | Frontend VPC | PERMIT |
| 20 | GKE Required GCP Services | All GKE | gcp_required WebGroup | PERMIT (HTTPS) |
| 21 | GKE Required GCP Services HTTP | All GKE | gcp_required WebGroup | PERMIT (HTTP) |
| 22 | Allow Kubernetes-io | All GKE | kubernetes_io WebGroup | PERMIT |
| 23 | Allow Docker Hub | All GKE | docker_hub WebGroup | PERMIT |
| 24 | Allow npm Registry | All GKE | npm_registry WebGroup | PERMIT |
| 25 | Allow GitHub Aviatrix Repos | All GKE | github_aviatrix WebGroup | PERMIT |

When `enable_k8s_smartgroup_demo = true` (default), an additional priority-50 rule fires between priorities 17 and 20:

| Priority | Name | Source | Destination | Action |
|---:|---|---|---|---|
| 50 | Frontend Gatus to Backend Gatus k8s ns selector | K8s-typed SG `frontend-gatus-ns` | K8s-typed SG `backend-gatus-ns` | PERMIT |

The implicit deny at the bottom of every policy list blocks anything not matched above.

---

## Day 2 Operations

### Scale Node Pools

The primary node pool autoscales from 1 to 3 nodes by default. To change the bounds:

```bash
cd clusters/frontend/
vim terraform.tfvars
# Edit node_pool_config = { initial_count = 2, min_count = 1, max_count = 3, machine_type = "e2-standard-2", disk_size_gb = 100 }

terraform apply
```

The `lifecycle { ignore_changes = [node_count] }` on the node pool means autoscale-driven node count changes won't drift Terraform state.

### Upgrade GKE Version

GKE clusters in this blueprint use the `REGULAR` release channel — masters auto-upgrade according to the channel cadence and node pools auto-upgrade by default (`management.auto_upgrade = true`). To force an immediate version change:

```bash
gcloud container clusters upgrade gke-demo-frontend \
  --zone us-central1-a --master \
  --cluster-version 1.33.x-gke.xxx
```

The Terraform `lifecycle { ignore_changes = [min_master_version] }` block means out-of-band master version drift won't show up as `terraform plan` noise.

### Add a New DCF WebGroup

```hcl
# In network/dcf.tf
resource "aviatrix_web_group" "wg_my_service" {
  name = "${var.name_prefix}-wg-my-service"
  selector {
    match_expressions {
      snifilter = "*.example.com"
    }
  }
}
```

Then add a rule to the policy list referencing the WebGroup. `terraform apply` in the network layer takes ~5 seconds.

---

## Destroy Instructions

Always destroy in **reverse order**. Three cross-layer dependencies need explicit cleanup that Terraform doesn't handle automatically:

1. **DCF CRs (`FirewallPolicy`, `WebGroupPolicy`) inject Controller-side state.** When the Aviatrix Controller's watch loop reconciles a CR it creates mirror SmartGroups and policy-list rules on the Controller (e.g., `firewallpolicysource-<ns>--<cr-name>--<cluster-hash>`, `webgrouppolicy-target-<ns>--<cr-name>--<cluster-hash>`, plus per-CR entries in the system `K8s Policy List` and per-CR `firewallpolicylist-*` lists). The watch loop **only garbage-collects this state when it observes a CR `delete` event on a still-reachable cluster.** If you destroy the cluster (or remove the Helm release that holds the CRDs) before the CRs are deleted, the watch loop never sees the delete and the Controller-side mirror state is **orphaned**. Orphans then block subsequent `aviatrix_kubernetes_cluster` destroy with `[AVXERR-SMARTGROUP-0003] ... present in one or more dfw policies`.
2. **K8s SmartGroups in the network layer pin the cluster registrations.** The `aviatrix_kubernetes_cluster` resource cannot be deleted while any SmartGroup references its `cluster_id`. Toggle them off via `enable_k8s_smartgroup_demo = false` before destroying clusters.
3. **ExternalDNS-created Cloud DNS records orphan if pods/Services are destroyed by Terraform without giving ExternalDNS a chance to issue the corresponding DNS deletes.** Always delete the Gatus manifests via `kubectl delete` first (graceful Service tear-down → ExternalDNS removes the A record) before tearing down the nodes layer.

### Step 1: Delete Kubernetes Resources (DCF CRs first, then Gatus)

> [!IMPORTANT]
> Order matters: delete the DCF CRs **before** deleting Gatus. The CR-injected `firewallpolicysource-*` and `webgrouppolicy-target-*` SmartGroups are scoped to namespaces that exist (e.g., `gatus`, `dev`) — if the namespace is gone before the CR is deleted, the watch loop's namespace-resolved reference fails and the mirror SG can be left in a state that's hard to clean up.

```bash
# 1a. Delete DCF CRs (the watch loop tears down its mirror SmartGroups + policy rules)
kubectl --context=frontend delete -f k8s-apps/dcf-crd/ --ignore-not-found
kubectl --context=backend  delete -f k8s-apps/dcf-crd/ --ignore-not-found

# 1b. Wait for the Controller's watch loop to finalize the deletions.
#     Empirically ~30-60s on Controller 9.0.10 for two CRs across two clusters.
sleep 60

# 1c. Verify the CR-injected mirror state is GONE before proceeding.
CID=$(curl -sk -X POST "https://${AVIATRIX_CONTROLLER_IP}/v1/api" \
  -d "action=login&username=${AVIATRIX_USERNAME}&password=${AVIATRIX_PASSWORD}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['CID'])")

echo "Looking for orphan CR-injected SmartGroups (should be empty):"
curl -sk -H "Authorization: cid ${CID}" "https://${AVIATRIX_CONTROLLER_IP}/v2.5/api/app-domains" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
for ad in d.get('app_domains', []):
    n = ad.get('name', '')
    if 'firewallpolicy' in n.lower() or 'webgrouppolicy' in n.lower():
        print(f'  {n}')"
# Expected: no output. If you see any names, the watch loop hasn't finalized yet —
# wait another 60s and re-check, or jump to the Recovery procedure at the bottom.

echo "Looking for orphan K8s policy-list rules (system list rules should be 0):"
curl -sk -H "Authorization: cid ${CID}" "https://${AVIATRIX_CONTROLLER_IP}/v2.5/api/microseg/policy-list3" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
for pl in d.get('dcf_policies', []):
    if pl.get('metadata', {}).get('k8s'):
        rules = pl.get('policies', [])
        print(f'  {pl.get(\"name\")} (uuid={pl.get(\"uuid\",\"\")[:8]}...) rules={len(rules)}')"
# Expected:
#   K8s Policy Block (uuid=defa11a1...) rules=0
#   K8s Policy List  (uuid=defa11a1...) rules=0
# Per-CR firewallpolicylist-* lists should NOT appear at all.

# 1d. Delete Gatus and the Gateway/HTTPRoute (triggers ExternalDNS DNS-record cleanup
#     and tears down the GKE Gateway-managed Global External ALB).
kubectl --context=frontend delete -f k8s-apps/frontend/gatus.yaml --ignore-not-found
kubectl --context=backend  delete -f k8s-apps/backend/gatus.yaml --ignore-not-found

# 1e. Wait for ExternalDNS to remove the Cloud DNS records (~30-60s).
sleep 60

# 1f. Verify Cloud DNS records are cleaned up (only db.* should remain — Terraform-managed)
gcloud dns record-sets list \
  --project=<YOUR_PROJECT_ID> \
  --zone=gke-demo-private-zone \
  --format="value(name)" | grep -E "frontend|backend"
# Expected: empty.
```

If 1c shows orphan SmartGroups after waiting 2 minutes, **do not proceed** — the watch loop didn't garbage-collect properly. Jump to the [Recovery: Orphaned CR-Injected State](#recovery-orphaned-cr-injected-state) procedure at the bottom of this section before continuing to Step 2.

### Step 2: Destroy Node Layers (Parallel)

```bash
# Terminal 1
cd nodes/frontend/ && terraform destroy

# Terminal 2
cd nodes/backend/ && terraform destroy
```

This removes the `external-dns` and `k8s-firewall` Helm releases. Removing `k8s-firewall` deletes the `FirewallPolicy` and `WebGroupPolicy` CRDs from the cluster — at this point the cluster has no DCF CRD support left, but that's fine because we already deleted all CRs in Step 1.

### Step 3: Disable K8s SmartGroup Demo

The K8s SmartGroups in `network/dcf-k8s.tf` and the priority-50 demo rule in `network/dcf.tf` reference the GKE cluster IDs. The Aviatrix Controller refuses to delete the `aviatrix_kubernetes_cluster` registration while any SmartGroup still references it. Disable both via the gating variable:

```bash
cd network/

# Removes the 4 K8s SmartGroups and the priority-50 rule. ~10s.
terraform apply -auto-approve -var enable_k8s_smartgroup_demo=false
```

> [!IMPORTANT]
> If this step fails with `[AVXERR-SMARTGROUP-0003] Smart Group ... present in one or more dfw policies`, it's the same kind of eventual-consistency hiccup the AKS variant documents. The `depends_on` in `dcf.tf` is supposed to remove the priority-50 rule from the policy list before the SG delete, but in some controller builds the dynamic-rule edge gets dropped. Recovery is mechanical:
>
> ```bash
> NAME_PREFIX=gke-demo
> CID=$(curl -sk -X POST "https://${AVIATRIX_CONTROLLER_IP}/v1/api" \
>   -d "action=login&username=${AVIATRIX_USERNAME}&password=${AVIATRIX_PASSWORD}" \
>   | python3 -c "import sys,json; print(json.load(sys.stdin)['CID'])")
>
> # Build a pruned copy of the policy list (priority-50 removed) and PUT it back.
> curl -sk -H "Authorization: cid ${CID}" \
>   "https://${AVIATRIX_CONTROLLER_IP}/v2.5/api/microseg/policy-list3" \
>   | NAME_PREFIX="$NAME_PREFIX" python3 -c "
> import sys, json, os
> target = os.environ['NAME_PREFIX'] + '-gke-multicluster'
> d = json.load(sys.stdin)
> for pl in d.get('dcf_policies', []):
>     if pl.get('name') == target:
>         pl['policies'] = [p for p in pl.get('policies', []) if p.get('priority') != 50]
>         print(json.dumps(pl)); break" > /tmp/gke-prune.json
> LIST_UUID=$(python3 -c "import json; print(json.load(open('/tmp/gke-prune.json'))['uuid'])")
> curl -sk -X PUT -H "Authorization: cid ${CID}" -H "Content-Type: application/json" \
>   --data-binary @/tmp/gke-prune.json \
>   "https://${AVIATRIX_CONTROLLER_IP}/v2.5/api/microseg/policy-list3/${LIST_UUID}"
>
> # Then re-run the apply — Terraform reconciles state and completes the SG destroys.
> terraform apply -auto-approve -var enable_k8s_smartgroup_demo=false
> ```

### Step 4: Destroy GKE Clusters (Parallel)

`terraform destroy` removes the `aviatrix_kubernetes_cluster` registration as well as the GKE cluster itself.

```bash
# Terminal 1
cd clusters/frontend/ && terraform destroy

# Terminal 2
cd clusters/backend/ && terraform destroy

# Verify no stale K8s cluster registrations remain on the controller
CID=$(curl -sk -X POST "https://${AVIATRIX_CONTROLLER_IP}/v1/api" \
  -d "action=login&username=${AVIATRIX_USERNAME}&password=${AVIATRIX_PASSWORD}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['CID'])")
curl -sk -H "Authorization: cid ${CID}" \
  "https://${AVIATRIX_CONTROLLER_IP}/v2.5/api/k8s/clusters"
# Expected: []  (or no entries for gke-demo-*)
```

If `terraform destroy` here fails with the `cluster is still used in smart groups: ..., firewallpolicysource-..., webgrouppolicy-target-...` error, Step 1 didn't clean up the CR-injected state. Run the [Recovery procedure](#recovery-orphaned-cr-injected-state) below, then re-run `terraform destroy`.

### Step 5: Destroy Network Layer

```bash
cd network/
terraform destroy -var enable_k8s_smartgroup_demo=false
```

The `-var` is needed so the destroy plan matches the live state from Step 3 (otherwise Terraform plans to re-create the K8s SmartGroups before destroying everything).

### Step 6: Clean Up kubectl Contexts (Optional)

```bash
# If you renamed the contexts in Step 7 of deployment
kubectl config delete-context frontend
kubectl config delete-context backend

# Otherwise the auto-generated names
kubectl config delete-context gke_<PROJECT>_us-central1-a_gke-demo-frontend
kubectl config delete-context gke_<PROJECT>_us-central1-a_gke-demo-backend
```

### Recovery: Orphaned CR-Injected State

If you skipped Step 1's CR cleanup OR the watch loop didn't finalize before the cluster was destroyed, you'll see one of these symptoms:

- `terraform destroy` on a cluster fails with:
  `failed to delete kubernetes cluster: HTTP DELETE ... cluster is still used in smart groups: ..., firewallpolicysource--<ns>--<cr-name>--<hash>, webgrouppolicy-target-<ns>--<cr-name>--<hash>`
- CoPilot → Security → SmartGroups still shows entries with names starting `firewallpolicy-`, `firewallpolicysource-`, or `webgrouppolicy-` after both clusters are destroyed.
- A `terraform plan` on `network/` shows phantom drift on system policy lists (`K8s Policy List`, `K8s Policy Block`).

These are Controller-side records the watch loop didn't get a chance to clean up. Remove them via the Controller API:

```bash
CID=$(curl -sk -X POST "https://${AVIATRIX_CONTROLLER_IP}/v1/api" \
  -d "action=login&username=${AVIATRIX_USERNAME}&password=${AVIATRIX_PASSWORD}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['CID'])")

# 1. Find K8s-injected per-CR policy lists (have metadata.k8s set, NOT system)
echo "=== Per-CR policy lists (delete these) ==="
curl -sk -H "Authorization: cid ${CID}" \
  "https://${AVIATRIX_CONTROLLER_IP}/v2.5/api/microseg/policy-list3" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
for pl in d.get('dcf_policies', []):
    md = pl.get('metadata', {})
    uuid = pl.get('uuid', '')
    # System lists start with defa11a1- and must be PUT-emptied, not DELETEd
    if md.get('k8s') and not uuid.startswith('defa11a1-'):
        print(f\"  DELETE: {pl.get('name')} (uuid={uuid})\")"

# 2. For each non-system list (UUID NOT starting with "defa11a1-"), DELETE:
curl -sk -X DELETE -H "Authorization: cid ${CID}" \
  "https://${AVIATRIX_CONTROLLER_IP}/v2.5/api/microseg/policy-list3/<uuid>"

# 3. For SYSTEM lists like "K8s Policy List" (defa11a1-3000-6000-4000-...), PUT
#    with empty policies array to clear injected rules WITHOUT deleting the list.
curl -sk -X PUT -H "Authorization: cid ${CID}" -H "Content-Type: application/json" \
  -d '{"name":"K8s Policy List","attach_to":"defa11a1-3000-6000-5000-000000000000","policies":[],"metadata":{"k8s":{"resource-type":"k8s-policylist"}}}' \
  "https://${AVIATRIX_CONTROLLER_IP}/v2.5/api/microseg/policy-list3/defa11a1-3000-6000-4000-000000000000"

# 4. Now the orphan SmartGroups can be deleted:
curl -sk -H "Authorization: cid ${CID}" \
  "https://${AVIATRIX_CONTROLLER_IP}/v2.5/api/app-domains" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
for ad in d.get('app_domains', []):
    n = ad.get('name', '')
    if any(p in n for p in ['firewallpolicy-', 'firewallpolicysource-', 'webgrouppolicy-']):
        print(ad['uuid'])
" | xargs -I {} curl -sk -X DELETE -H "Authorization: cid ${CID}" \
      "https://${AVIATRIX_CONTROLLER_IP}/v2.5/api/app-domains/{}"

# 5. Verify clean
curl -sk -H "Authorization: cid ${CID}" \
  "https://${AVIATRIX_CONTROLLER_IP}/v2.5/api/app-domains" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('Remaining CR-related app-domains:')
for ad in d.get('app_domains', []):
    n = ad.get('name', '')
    if any(p in n for p in ['firewallpolicy-', 'firewallpolicysource-', 'webgrouppolicy-']):
        print(f'  STILL PRESENT: {n}')"
# Expected: empty (no STILL PRESENT lines).

# 6. Resume Step 4 (cluster destroy) — or Step 3 if the SmartGroup demo toggle failed.
```

---

## Troubleshooting

### Pods Can't Reach the Internet

1. **Verify the priority-991 default route is programmed in the spoke VPC:**
   ```bash
   gcloud compute routes list --project=<PROJECT> \
     --filter="network:gke-demo-frontend-vpc AND priority=991" \
     --format="table(name,priority,destRange,nextHopInstance.basename(),tags.list())"
   ```
   Expected: one untagged 991 route → `gke-demo-frontend-spoke`. If missing, the spoke gateway didn't finish provisioning — check `terraform apply` output and the controller's `Site2Cloud → IPSec` page.

2. **Verify CONDUIT_SNAT is firing on the spoke GW:**
   ```bash
   ssh -tt -i <key.pem> ubuntu@$AVIATRIX_CONTROLLER_IP \
     "bash -lic 'sshgw gke-demo-frontend-spoke -- sudo iptables -t nat -L CONDUIT_SNAT -v -n'"
   ```
   The rule `SNAT 100.64.0.0/16 → eth0 → 10.10.4.2` should have non-zero packet counters when pods are sending traffic. If zero counters but pods exist, traffic isn't reaching the spoke GW — check the priority-991 route and the GKE cluster's `default_snat_status.disabled`.

3. **Verify the GKE node SA has the right roles:**
   ```bash
   gcloud projects get-iam-policy <PROJECT> \
     --flatten="bindings[].members" \
     --filter="bindings.members~gke-demo-frontend-node-sa" \
     --format="value(bindings.role)"
   ```
   Should include `logging.logWriter`, `monitoring.metricWriter`, `monitoring.viewer`, `stackdriver.resourceMetadata.writer`, `artifactregistry.reader`.

### GKE Gateway Stuck in `PROGRAMMED=False`

The GKE Gateway controller takes 3-5 minutes to provision the Global External ALB on first deploy. If it's still false after 10 minutes:

1. **Check Gateway events:**
   ```bash
   kubectl --context=frontend describe gateway frontend-public -n gatus
   ```
   Common errors: missing `networking.gke.io/addresses` annotation pointing at a reserved global address, or the reserved address has a region (must be `EXTERNAL` global).

2. **Verify the reserved address exists and is unattached:**
   ```bash
   gcloud compute addresses list --global --filter="name~gke-demo-.*-gateway-ip" \
     --format="table(name,address,addressType,status)"
   ```
   Status `RESERVED` is normal until the Gateway claims it (becomes `IN_USE`).

3. **Check Gateway events + GKE control-plane audit logs.** The `gke-l7-global-external-managed` controller is **GKE-managed** (runs outside your cluster) — there is no in-cluster pod or `gke-system` deployment to log against. Use:
   ```bash
   kubectl --context=frontend get events -n gatus \
     --field-selector involvedObject.kind=Gateway,involvedObject.name=frontend-public \
     --sort-by=.lastTimestamp
   gcloud logging read 'resource.type="gke_cluster" AND severity>=ERROR' \
     --project=<PROJECT> --limit=50 --format="value(timestamp,textPayload)"
   ```

### ExternalDNS Not Creating DNS Records

1. **Check ExternalDNS pod logs:**
   ```bash
   kubectl --context=frontend logs -n kube-system -l app.kubernetes.io/name=external-dns --tail=20
   ```

2. **Verify the Workload Identity binding:**
   ```bash
   kubectl --context=frontend describe sa external-dns -n kube-system
   # Annotations should include iam.gke.io/gcp-service-account
   ```

3. **Verify the GSA has DNS admin role:**
   ```bash
   gcloud projects get-iam-policy <PROJECT> \
     --flatten="bindings[].members" \
     --filter="bindings.members~gke-demo-frontend-edns" \
     --format="value(bindings.role)"
   # Should include: roles/dns.admin
   ```

### GKE Cluster Shows "Onboarded: No" in CoPilot, or DCF CRs Aren't Reconciled

After `clusters/*` and `nodes/*` apply succeed and you've applied DCF CRs from `k8s-apps/dcf-crd/`, but you don't see CR-injected SmartGroups in CoPilot (no `firewallpolicysource-*` or `webgrouppolicy-target-*` entries) and the system `K8s Policy List` shows 0 rules — the watch loop isn't reconciling. Walk these in order:

1. **Check that the Controller's egress IP is in the GKE master allowlist:**
   ```bash
   gcloud container clusters describe gke-demo-frontend \
     --zone us-central1-a --project <PROJECT> \
     --format="value(masterAuthorizedNetworksConfig.cidrBlocks[].cidrBlock)"
   # Expect to see: <controller_public_ip>/32, <spoke_gw_public_ip>/32, your IP
   ```
   If the controller IP is missing, set `aviatrix_controller_public_ip` in the cluster's `terraform.tfvars` and re-apply. (When `master_authorized_cidr_blocks = ["0.0.0.0/0"]`, this isn't needed — the controller is implicitly allowed.)

2. **Verify the Aviatrix GCP access account's SA has GKE permissions:**
   ```bash
   # Find the access account's SA email
   SA_EMAIL=$(curl -sk -H "Authorization: cid ${CID}" \
     "https://${AVIATRIX_CONTROLLER_IP}/v1/api?action=list_accounts&CID=${CID}" \
     | python3 -c "
   import sys, json
   d = json.load(sys.stdin)
   for a in d['results']['account_list']:
       if a.get('account_name') == 'Google':
           print(a.get('gcloud_project_credentials_filename', ''))")

   # Show roles assigned to that SA on the project
   gcloud projects get-iam-policy <PROJECT> \
     --flatten="bindings[].members" \
     --filter="bindings.members:${SA_EMAIL}" \
     --format="value(bindings.role)"
   # Required permissions: container.clusters.get, container.clusters.getCredentials.
   # roles/editor, roles/container.admin, roles/container.clusterAdmin all include them.
   # roles/container.clusterViewer alone is NOT sufficient — it lacks getCredentials.
   ```

3. **Confirm the cluster registration exists on the Controller:**
   ```bash
   CID=$(curl -sk -X POST "https://${AVIATRIX_CONTROLLER_IP}/v1/api" \
     -d "action=login&username=${AVIATRIX_USERNAME}&password=${AVIATRIX_PASSWORD}" \
     | python3 -c "import sys,json; print(json.load(sys.stdin)['CID'])")
   curl -sk -H "Authorization: cid ${CID}" \
     "https://${AVIATRIX_CONTROLLER_IP}/v2.5/api/k8s/clusters" | python3 -m json.tool
   ```
   Both clusters should appear with `use_csp_credentials: true`.

4. **Confirm the watch loop is actually reconciling.** The fastest way is to look for CR-injected SmartGroups + system-list rules:
   ```bash
   echo "=== CR-injected SmartGroups (subsequent CR applies on an already-onboarded cluster reconcile within ~60s; the first reconcile after a fresh onboarding can take up to ~10-15 minutes) ==="
   curl -sk -H "Authorization: cid ${CID}" "https://${AVIATRIX_CONTROLLER_IP}/v2.5/api/app-domains" \
     | python3 -c "
   import sys, json
   d = json.load(sys.stdin)
   for ad in d.get('app_domains', []):
       n = ad.get('name', '')
       if 'firewallpolicy' in n.lower() or 'webgrouppolicy' in n.lower():
           print(f'  {n}')"
   # Expected after applying k8s-apps/dcf-crd/:
   #   firewallpolicy-gatus--infosec-egress--security-tools--<hash>
   #   firewallpolicy-smartgroup-gatus--infosec-egress--public-internet--<hash>
   #   firewallpolicysource--gatus--infosec-egress--<hash>--2--0
   #   webgrouppolicy-dev--dev-external-apis--<hash>
   #   webgrouppolicy-target-dev--dev-external-apis--<hash>

   echo "=== K8s system policy lists (should have 1+ rule per CR) ==="
   curl -sk -H "Authorization: cid ${CID}" "https://${AVIATRIX_CONTROLLER_IP}/v2.5/api/microseg/policy-list3" \
     | python3 -c "
   import sys, json
   d = json.load(sys.stdin)
   for pl in d.get('dcf_policies', []):
       if pl.get('metadata', {}).get('k8s'):
           print(f\"  {pl.get('name')} rules={len(pl.get('policies',[]))}\")"
   # Expected:
   #   K8s Policy Block rules=0       (nothing in the FirewallPolicy DENY semantics for these CRs)
   #   K8s Policy List  rules=2       (one per cluster, from webgrouppolicy)
   #   firewallpolicylist-gatus--infosec-egress--<hash> rules=1   (one per cluster, from firewallpolicy)
   ```
   If the registration exists (step 3) but the SmartGroups + rules in step 4 are missing, try **forcing a re-onboard**:
   ```bash
   cd clusters/frontend/
   terraform taint 'aviatrix_kubernetes_cluster.this[0]'
   terraform apply
   ```
   The taint causes Terraform to delete and re-create the registration, which re-triggers the controller's onboarding handshake. Wait ~60s after apply for the watch loop to spin up, then re-check step 4.

   **Note:** if the destroy half of the taint fails with `cluster is still used in smart groups: <name1>, <name2>, ...`, inspect the names. If any start with `firewallpolicysource-` or `webgrouppolicy-target-`, the watch loop IS reconciling CRs — registration is healthy, check CoPilot UI for member resolution. If only template-level SGs (e.g. `${name_prefix}-sg-*-cluster`, `${name_prefix}-sg-*-gatus-ns`) appear, the test is **inconclusive** — those are created by `network/dcf-k8s.tf` (when `enable_k8s_smartgroup_demo = true`), not by the watch loop. In that case, set `enable_k8s_smartgroup_demo = false` on `network/`, apply, then retry the taint to isolate watch-loop behavior.

5. **Check CoPilot directly.** The controller API only confirms registration; CoPilot is the only surface that exposes resolved pod-IP membership for K8s-typed SmartGroups. Cloud Workloads → Kubernetes Clusters should show **Onboarded: Yes** with namespace and pod counts. First-time sync after onboarding can take up to ~10 minutes.

### Cross-Cluster East-West Pings/Curls Time Out

1. **Verify the priority-991 route on both spoke VPCs** (see "Pods Can't Reach the Internet" #1).

2. **Verify CONDUIT_SNAT has the transit-direction rule** (rule 2 in the chain — `dst-group 0x1`):
   ```bash
   ssh -tt -i <key.pem> ubuntu@$AVIATRIX_CONTROLLER_IP \
     "bash -lic 'sshgw gke-demo-frontend-spoke -- sudo iptables -t nat -L CONDUIT_SNAT -v -n'"
   ```
   If only the eth0 rule exists, the `connection = module.gcp_transit.transit_gateway.gw_name` policy didn't apply — check the network layer's `aviatrix_gateway_snat` resource state.

3. **Verify the IPsec tunnel is up (Aviatrix CoPilot → Topology):** both spoke gateways should show green to the transit gateway.

4. **Check transit-side BGP** for the pod CIDR. The blueprint uses `excluded_advertised_spoke_routes = "100.64.0.0/16"` so pod CIDRs are NOT advertised to peers (that's intentional — SNAT covers it).

### Aviatrix Controller Errors on `aviatrix_gateway_snat` Apply

If the apply fails with `Failed to register gateway with controller` or `gateway not ready`:

1. The spoke gateway and the SNAT resource race during first apply. **Wait 30-60 seconds and re-run `terraform apply`** — the spoke GW finishes its IPsec tunnel setup and accepts the SNAT config on the retry.

2. Check the controller's `Multi-Cloud Transit → Gateways` page. The spoke gateway should show **Up** with all tunnels green.

### Terraform Remote State Errors

If a layer fails with `No such file or directory` for a state file:
```
Error: Failed to read state file
path = "../../network/terraform.tfstate"
```

Ensure the previous layer has been successfully applied:
```bash
ls -la network/terraform.tfstate
ls -la clusters/frontend/terraform.tfstate
```

The deployment order is `network → clusters → nodes`. Each layer requires the previous to have completed `terraform apply`.

### `gke-gcloud-auth-plugin` Not Found

```
error: gke-gcloud-auth-plugin must be installed
```

Install:
```bash
gcloud components install gke-gcloud-auth-plugin
```

After installing, re-run `gcloud container clusters get-credentials` so kubeconfig regenerates with the correct exec credential.

---

## Resource Inventory

### Compute Resources

| Component | Resource Type | Qty | Machine Type | Notes |
|-----------|---------------|----:|--------------|-------|
| **Aviatrix Gateways** | | | | |
| Transit GW | GCE VM | 1 | n1-standard-1 | Zonal (us-central1-a), no HA |
| Frontend Spoke GW | GCE VM | 1 | n1-standard-1 | `customized_snat`, no HA |
| Backend Spoke GW | GCE VM | 1 | n1-standard-1 | `customized_snat`, no HA |
| DB Spoke GW | GCE VM | 1 | n1-standard-1 | `single_ip_snat`, no HA |
| **GKE** | | | | |
| Frontend Control Plane | GKE | 1 | — | Zonal, REGULAR channel, Free tier |
| Backend Control Plane | GKE | 1 | — | Zonal, REGULAR channel, Free tier |
| Frontend Node Pool | GCE MIG | 2 (desired) | e2-standard-2 | min=1, max=3, autoscale |
| Backend Node Pool | GCE MIG | 2 (desired) | e2-standard-2 | min=1, max=3, autoscale |
| **Test VM** | | | | |
| DB Linux VM | GCE VM | 1 | e2-small | DB spoke, Apache |

**Total VMs (at desired state):** 9

### Networking Resources

| Component | Qty | Details |
|-----------|----:|---------|
| VPCs | 4 | Transit (`10.2.0.0/24`), Frontend (`10.10.0.0/20`), Backend (`10.20.0.0/20`), DB (`10.5.0.0/22`) |
| Subnets | 11 | Per spoke VPC: nodes, Aviatrix GW, proxy-only. DB: VMs subnet + Aviatrix GW subnet. Transit: 1. |
| Cloud Routes (Aviatrix-managed) | ~16 | Per spoke: priority-500 IGW (tagged), priority-991 default (untagged) → spoke GW, three RFC1918 → spoke GW |
| Reserved Global IPv4 | 2 | One per cluster's GKE Gateway |
| Cloud DNS Private Zone | 1 | `gcp.aviatrixdemo.local.` linked to all 3 spoke VPCs |
| Static DNS Records | 1 | `db.gcp.aviatrixdemo.local` → DB VM IP |
| GCP Firewall Rules | ~12 | Created by `gke-vpc` module (allow internal + allow GKE control plane to nodes) |

### Subnet Layout (per Spoke VPC, example: Frontend `10.10.0.0/20`)

| Subnet Name | CIDR | Size | Purpose | Secondary Ranges |
|---|---|---:|---|---|
| `gke-demo-frontend-nodes` | `10.10.0.0/22` | 1024 IPs | GKE node VMs | pods (`100.64.0.0/16`), services (`172.16.0.0/20`) |
| `gke-demo-frontend-avx-gw` | `10.10.4.0/28` | 16 IPs | Aviatrix spoke gateway | — |
| `gke-demo-frontend-proxy-only` | `10.10.5.0/24` | 256 IPs | GKE Gateway proxies | — |

### DCF Inventory

| Component | Qty | Names (with `name_prefix = gke-demo`) |
|---|---:|---|
| SmartGroups (VPC-typed) | 4 | `gke-demo-sg-{frontend,backend,db}-vpc`, `gke-demo-sg-all-gke` |
| SmartGroups (service-typed) | 3 | `gke-demo-sg-{frontend,backend}-service`, `gke-demo-sg-database` |
| SmartGroups (threat) | 2 | `gke-demo-sg-geo-blocked`, `gke-demo-sg-threat-intel` |
| SmartGroups (K8s-typed, gated) | 4 | `gke-demo-sg-{frontend,backend}-cluster`, `gke-demo-sg-{frontend,backend}-gatus-ns` |
| WebGroups | 5 | `gke-demo-wg-{kubernetes-io,docker-hub,npm-registry,github-aviatrix,gcp-required}` |
| Policy lists | 1 | `gke-demo-gke-multicluster` (12 rules + optional priority-50) |

---

## Monthly Cost Estimate (us-central1, On-Demand)

> Prices are on-demand rates as of early 2026. Actual costs vary with traffic, autoscaling, sustained-use discounts (up to ~30% on continuous VMs), and committed-use discounts (up to ~57%). Aviatrix licensing is billed separately and not included below.

### Compute

| Resource | Machine Type | Qty | Hourly | Monthly (730 hrs) |
|---|---|---:|---:|---:|
| Aviatrix Transit GW | n1-standard-1 | 1 | $0.0475 | $34.68 |
| Aviatrix Frontend Spoke GW | n1-standard-1 | 1 | $0.0475 | $34.68 |
| Aviatrix Backend Spoke GW | n1-standard-1 | 1 | $0.0475 | $34.68 |
| Aviatrix DB Spoke GW | n1-standard-1 | 1 | $0.0475 | $34.68 |
| GKE Frontend Nodes | e2-standard-2 | 2 | $0.0670 ea | $97.82 |
| GKE Backend Nodes | e2-standard-2 | 2 | $0.0670 ea | $97.82 |
| DB Test VM | e2-small | 1 | $0.0167 | $12.19 |
| **Subtotal Compute** | | | | **$346.55** |

### GKE Control Plane

| Resource | Tier | Qty | Hourly | Monthly |
|---|---|---:|---:|---:|
| Frontend Control Plane | Standard (zonal) | 1 | $0.10 | $73.00 |
| Backend Control Plane | Standard (zonal) | 1 | $0.10 | $73.00 |
| **Subtotal GKE Control Plane** | | | | **$146.00** |

> GKE Standard charges $0.10/hr per cluster. The first cluster per billing account is free under the GKE free tier.

### Load Balancers (Global External ALB)

| Component | Rate | Qty | Monthly |
|---|---:|---:|---:|
| GKE Gateway forwarding rules | $0.025/hr | 2 | $36.50 |
| Data processing | $0.008/GB | ~20 GB | ~$0.16 |
| **Subtotal Load Balancers** | | | **~$36.66** |

### Networking

| Resource | Rate | Qty | Monthly |
|---|---:|---:|---:|
| Reserved Global Static IPs (when in use) | Free while attached | 2 | $0.00 |
| Cloud DNS Private Zone | $0.20/zone/month | 1 | $0.20 |
| Cloud DNS queries | $0.40/M (first 1B) | ~1M | ~$0.40 |
| VPC, subnets, routes | Free | — | $0.00 |
| **Subtotal Networking** | | | **~$0.60** |

### Storage

| Resource | Type | Qty | Monthly |
|---|---|---:|---:|
| GKE Node OS Disks (100 GB pd-balanced) | Persistent disk balanced | 4 | $40.00 |
| Aviatrix GW OS Disks (~10 GB pd-standard) | Persistent disk standard | 4 | ~$1.60 |
| DB VM OS Disk (10 GB pd-balanced) | Persistent disk balanced | 1 | $1.00 |
| **Subtotal Storage** | | | **~$42.60** |

### Data Transfer (Estimated for Lab Workloads)

| Type | Est. Volume | Rate | Monthly |
|---|---:|---:|---:|
| Cross-VPC via Aviatrix transit (in-region) | ~50 GB | Free (same region) | $0.00 |
| Internet egress | ~10 GB | $0.12/GB | ~$1.20 |
| **Subtotal Data Transfer** | | | **~$1.20** |

### Total Estimated Monthly Cost

| Category | Cost |
|---|---:|
| Compute | $346.55 |
| GKE Control Plane | $146.00 |
| Load Balancers | $36.66 |
| Networking | $0.60 |
| Storage | $42.60 |
| Data Transfer | $1.20 |
| **Total** | **~$573/month** |

> **Lab cost optimization:** if you run this only during business hours (8 hrs × 22 days = 176 hrs/month vs 730), you can scale to **~$138/month**. For destroy-and-redeploy daily use (40 hrs/month), expect **~$31/month**. The bulk of the cost is the four `n1-standard-1` Aviatrix gateways + four `e2-standard-2` GKE nodes + two GKE control planes.

---

## Networking Details

### CIDR Plan

| Layer | CIDR | Notes |
|---|---|---|
| Aviatrix Transit | `10.2.0.0/24` | Single-AZ transit GW. `excluded_advertised_spoke_routes = 100.64.0.0/16`. |
| Frontend VPC | `10.10.0.0/20` | nodes `10.10.0.0/22`, GW `10.10.4.0/28`, proxy-only `10.10.5.0/24` |
| Backend VPC | `10.20.0.0/20` | nodes `10.20.0.0/22`, GW `10.20.4.0/28`, proxy-only `10.20.5.0/24` |
| DB VPC | `10.5.0.0/22` | VMs `10.5.0.0/24`, GW `10.5.1.0/28` |
| GKE pods (both clusters) | `100.64.0.0/16` | Overlapping by design — Aviatrix `customized_snat` makes overlap invisible east-west |
| GKE services (both clusters) | `172.16.0.0/20` | ClusterIP range; never leaves the cluster |
| Frontend GKE master | `172.20.0.0/28` | Private master endpoint range |
| Backend GKE master | `172.20.1.0/28` | Private master endpoint range |

### Cloud Route Tables (per Spoke VPC)

The Aviatrix Controller programs four routes per spoke VPC. With `name_prefix = gke-demo`, on the frontend VPC:

| Priority | Destination | Next Hop | Tags | Purpose |
|---:|---|---|---|---|
| 500 | `0.0.0.0/0` | `default-internet-gateway` | `avx-gke-demo-frontend-vpc-gbl` | Spoke GW VM's own internet egress |
| 991 | `0.0.0.0/0` | spoke GW VM | (none — untagged per AVX-71737) | All other VMs (GKE nodes, pods) → spoke GW |
| 1000 | `10.0.0.0/8` | spoke GW VM | (none) | RFC1918 → transit |
| 1000 | `172.16.0.0/12` | spoke GW VM | (none) | RFC1918 → transit |
| 1000 | `192.168.0.0/16` | spoke GW VM | (none) | RFC1918 → transit |

The priority-500 route is the lowest-priority `0/0 → IGW` route that exists, but its tag (`avx-<vpc>-gbl`) restricts it to the Aviatrix GW VM. The priority-991 route is **untagged**, so it applies to every other VM in the VPC including GKE nodes and pods. This is the heart of how Aviatrix gets pod traffic to the spoke GW for SNAT and DCF inspection.

---

## Tested With

| Component | Version |
|---|---|
| Terraform | 1.14.0 |
| Aviatrix Provider (`AviatrixSystems/aviatrix`) | ~> 8.2 (8.2.0 verified) |
| Google Provider (`hashicorp/google`) | ~> 6.0 (6.50.0 verified) |
| Kubernetes Provider (`hashicorp/kubernetes`) | ~> 2.30 |
| Helm Provider (`hashicorp/helm`) | ~> 2.16 |
| Aviatrix Controller | 9.0.10-1000.116 |
| Aviatrix CoPilot | 9.0.x |
| Aviatrix Gateway Image | 9.0.10-1000.116 |
| Aviatrix `mc-transit` module | ~> 8.0 (8.2.0 verified) |
| Aviatrix `mc-spoke` module | ~> 8.0 (8.2.3 verified) |
| GKE | 1.33 (REGULAR channel, varies — see `kubectl version` after deploy) |
| ExternalDNS Helm chart | 1.15.0 |
| Aviatrix `k8s-firewall` Helm chart | 1.0.0 |
| `gcloud` SDK | latest |
| `kubectl` | latest |

---

## Variables

### `network/` Layer Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `name_prefix` | string | `"gke-demo"` | Prefix for all resource names. |
| `aviatrix_controller_ip` | string | `null` | Aviatrix Controller IP/hostname. Leave null and export `AVIATRIX_CONTROLLER_IP` instead. |
| `aviatrix_username` | string | `null` | Aviatrix Controller username. Leave null and export `AVIATRIX_USERNAME` instead. |
| `aviatrix_password` | string (sensitive) | `null` | Aviatrix Controller password. Leave null and export `AVIATRIX_PASSWORD` instead. |
| `aviatrix_gcp_account_name` | string | — | **Required.** Aviatrix GCP access account name (configured in Controller — typically `"Google"`). |
| `gcp_project_id` | string | — | **Required.** GCP project that owns the VPCs, GKE clusters, and DB VM. |
| `gcp_region` | string | `"us-central1"` | GCP region for subnets and zonal resources. |
| `gcp_zone` | string | `"us-central1-a"` | GCP zone for zonal GKE clusters and the DB VM. |
| `gw_instance_size` | string | `"n1-standard-1"` | GCE machine type for the Aviatrix transit + spoke gateways. Step up to `n1-standard-4` or higher for bandwidth-heavy workloads. |
| `transit_cidr` | string | `"10.2.0.0/24"` | CIDR for the Aviatrix Transit VPC. |
| `frontend_vpc_cidr` | string | `"10.10.0.0/20"` | Aggregate CIDR documented for the frontend VPC. |
| `frontend_nodes_cidr` | string | `"10.10.0.0/22"` | Primary CIDR for the frontend GKE node subnet. |
| `frontend_avx_gw_cidr` | string | `"10.10.4.0/28"` | Aviatrix spoke GW subnet CIDR for frontend. |
| `frontend_proxy_only_cidr` | string | `"10.10.5.0/24"` | Regional proxy-only subnet CIDR for frontend (used by GCP-managed L7 ALB / Gateway API). |
| `frontend_master_cidr` | string | `"172.20.0.0/28"` | GKE control-plane CIDR (/28) for the frontend cluster. |
| `backend_vpc_cidr` | string | `"10.20.0.0/20"` | Aggregate CIDR documented for the backend VPC. |
| `backend_nodes_cidr` | string | `"10.20.0.0/22"` | Primary CIDR for the backend GKE node subnet. |
| `backend_avx_gw_cidr` | string | `"10.20.4.0/28"` | Aviatrix spoke GW subnet CIDR for backend. |
| `backend_proxy_only_cidr` | string | `"10.20.5.0/24"` | Regional proxy-only subnet CIDR for backend. |
| `backend_master_cidr` | string | `"172.20.1.0/28"` | GKE control-plane CIDR (/28) for the backend cluster. |
| `db_vpc_cidr` | string | `"10.5.0.0/22"` | Aggregate CIDR for the DB test VPC. |
| `db_subnet_cidr` | string | `"10.5.0.0/24"` | Primary subnet CIDR for the DB test VM. |
| `db_avx_gw_cidr` | string | `"10.5.1.0/28"` | Aviatrix spoke GW subnet CIDR for the DB VPC. |
| `frontend_pods_cidr` | string | `"100.64.0.0/16"` | Pod alias range for the frontend GKE cluster. Default overlaps with backend by design (Aviatrix spoke GW SNATs pod IPs); use non-overlapping ranges for working east-west on GCP. |
| `backend_pods_cidr` | string | `"100.64.0.0/16"` | Pod alias range for the backend GKE cluster. See `frontend_pods_cidr` notes. |
| `services_cidr` | string | `"172.16.0.0/20"` | GKE Services secondary range — overlapping by design (kube-internal, never leaves the cluster). |
| `private_dns_zone_name` | string | `"gcp.aviatrixdemo.local."` | Cloud DNS private zone DNS name (must end with `.`). |
| `enable_k8s_smartgroup_demo` | bool | `true` | Create K8s-typed SmartGroups + the priority-50 demo DCF rule. Set to `false` and apply BEFORE destroying clusters/* (the K8s registration cannot be deleted while these SmartGroups reference its `cluster_id`). |

### `clusters/<frontend|backend>/` Layer Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `node_pool_config` | object | `{ machine_type = "e2-standard-2", disk_size_gb = 50, initial_count = 2, min_count = 1, max_count = 3 }` | Sizing for the primary GKE node pool. |
| `master_authorized_cidr_blocks` | list(string) | `["0.0.0.0/0"]` | User CIDR blocks allowed to reach the GKE master endpoint. The Aviatrix spoke GW egress IP and (when onboarding is on) the Controller IP are appended automatically. |
| `enable_aviatrix_onboarding` | bool | `true` | Register this GKE cluster with the Aviatrix Controller so DCF SmartGroups can target k8s clusters/namespaces/services/pods. |
| `aviatrix_controller_ip` | string | `null` | Aviatrix Controller IP/hostname (or set `AVIATRIX_CONTROLLER_IP` env var). |
| `aviatrix_username` | string | `null` | Aviatrix Controller username (or set `AVIATRIX_USERNAME` env var). |
| `aviatrix_password` | string (sensitive) | `null` | Aviatrix Controller password (or set `AVIATRIX_PASSWORD` env var). |
| `aviatrix_controller_public_ip` | string | `null` | Public egress IP of the Controller, appended to GKE `master_authorized_networks` when `enable_aviatrix_onboarding = true`. Required only when `master_authorized_cidr_blocks` is restrictive. |

### `nodes/<frontend|backend>/` Layer Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `external_dns_chart_version` | string | `"1.15.0"` | ExternalDNS Helm chart version (must support `gateway-httproute` source — chart >= 1.14). |
| `k8s_firewall_chart_version` | string | `"9.0.0"` | Aviatrix k8s-firewall Helm chart version (8.2.0 or 9.0.0 — published in https://aviatrixsystems.github.io/k8s-firewall-charts/index.yaml). |

---

## Outputs

### `network/` Layer Outputs

| Output | Type | Description |
|---|---|---|
| `name_prefix` | string | The blueprint's `name_prefix` (default `gke-demo`). Used by downstream layers for resource naming. |
| `gcp_project_id` | string | The GCP project ID. |
| `gcp_region` | string | The GCP region (e.g., `us-central1`). |
| `gcp_zone` | string | The GCP zone (e.g., `us-central1-a`). |
| `private_dns_zone_name` | string | Cloud DNS private zone DNS name (`gcp.aviatrixdemo.local.`). |
| `frontend_cluster_name` / `backend_cluster_name` | string | GKE cluster name (e.g., `gke-demo-frontend`). |
| `frontend_cluster_id` / `backend_cluster_id` | string | GKE cluster `self_link` (used by Aviatrix Controller for K8s SmartGroups). |
| `frontend_vpc_name` / `backend_vpc_name` | string | VPC name. |
| `frontend_vpc_self_link` / `backend_vpc_self_link` | string | VPC self-link (consumed by `clusters/`). |
| `frontend_nodes_subnet_name` / `backend_nodes_subnet_name` | string | Node subnet name. |
| `frontend_pods_range_name` / `backend_pods_range_name` | string | Pod alias range name. |
| `frontend_services_range_name` / `backend_services_range_name` | string | Service alias range name. |
| `frontend_master_cidr` / `backend_master_cidr` | string | GKE master endpoint CIDR. |
| `frontend_spoke_gateway_public_ip` / `backend_spoke_gateway_public_ip` | string | Spoke GW public egress IP (also the SNAT source for pod-to-internet). |
| `frontend_gateway_global_ip_name` / `backend_gateway_global_ip_name` | string | Reserved global IPv4 resource name (referenced by GKE Gateway). |
| `frontend_gateway_global_ip_address` / `backend_gateway_global_ip_address` | string | The actual IPv4 address (this is what you point a browser at). |
| `frontend_pods_cidr` / `backend_pods_cidr` | string | Pod CIDR (default `100.64.0.0/16` for both). |
| `services_cidr` | string | Service CIDR (default `172.16.0.0/20`). |
| `dcf_ruleset_uuid` | string | UUID of the DCF policy list. |
| `smartgroup_*_uuid` | string | UUIDs of all SmartGroups (for cross-layer references). |
| `webgroup_*_uuid` | string | UUIDs of all WebGroups. |

### `clusters/<x>/` Layer Outputs

| Output | Type | Description |
|---|---|---|
| `cluster_name` | string | GKE cluster name. |
| `cluster_endpoint` | string | GKE master endpoint hostname (no `https://` prefix). |
| `cluster_ca_certificate` | string (sensitive) | Cluster CA in base64. |
| `cluster_self_link` | string | Cluster self-link. |
| `external_dns_service_account_email` | string | GSA email for the ExternalDNS Workload Identity binding. |
| `node_service_account_email` | string | GSA email for the node pool. |
| `workload_identity_pool` | string | Workload Identity pool (`<project>.svc.id.goog`). |

### `nodes/<x>/` Layer Outputs

| Output | Type | Description |
|---|---|---|
| `external_dns_namespace` | string | Always `kube-system`. |
| `k8s_firewall_namespace` | string | Always `k8s-firewall`. |

---

## Known Limitations

- **No HA on Aviatrix gateways.** All gateways are deployed `ha_gw = false` for cost reasons. For production, set `ha_gw = true` on each `mc-spoke` and `mc-transit` module call.
- **Single-zone GKE clusters.** Both clusters are zonal (us-central1-a). For HA across zones, switch to a regional cluster (`location = local.region`) and update `clusters/*/main.tf`'s `frontend_cluster_id` local in `network/main.tf` to use `/locations/<region>/` instead of `/zones/<zone>/`.
- **Single project.** All VPCs and clusters live in one GCP project. Cross-project Aviatrix transit is supported by the controller but requires Shared VPC setup not in this blueprint.
- **DB VM is unmanaged.** Apache is installed via startup-script and not Terraform-managed beyond the VM. Reapply the VM module to refresh.

---

## Additional Resources

- [Aviatrix Distributed Cloud Firewall (DCF) Documentation](https://docs.aviatrix.com/documentation/latest/network-security/distributed-cloud-firewall.html)
- [Aviatrix `mc-spoke` module on Terraform Registry](https://registry.terraform.io/modules/terraform-aviatrix-modules/mc-spoke/aviatrix)
- [Aviatrix `mc-transit` module on Terraform Registry](https://registry.terraform.io/modules/terraform-aviatrix-modules/mc-transit/aviatrix)
- [GKE Gateway API](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api)
- [GKE Dataplane V2](https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2)
- [ExternalDNS for GCP Cloud DNS](https://kubernetes-sigs.github.io/external-dns/v0.14.0/tutorials/gke/)
- Sibling blueprints: [`aws-eks-multicluster`](../aws-eks-multicluster/), [`azure-aks-multicluster`](../azure-aks-multicluster/)

---

## GCP-Specific Gotchas (Reference)

These are the GCP-only quirks worth knowing if you adapt this blueprint:

- **Aviatrix `vpc_id` for GCP** has the form `<vpc_name>~-~<project_id>`, not the GCP self-link. Composed locally in `gke-vpc/outputs.tf`.
- **Aviatrix gateway `region`** for GCP is a **zone** (`us-central1-a`), not a region. Aviatrix gateways on GCP are zonal.
- **`single_ip_snat = true` only covers internet egress on GCP.** Cross-cluster east-west via the IPsec transit is **not** SNATed. With overlapping pod CIDRs, this leads to pod-IP collisions at the destination spoke. Use `customized_snat` with explicit `connection =` policies (as this blueprint does).
- **GKE secondary alias ranges aren't enumerated in the controller's `vpc_cidr` list.** This was previously believed to break customized_snat route programming on GCP — verified end-to-end on Controller 9.0.10-1000.116 that the priority-991 default route is programmed correctly via the spoke-creation path, independent of the SNAT policy. Cross-validated by `gcloud compute routes list` after `terraform apply` of this blueprint.
- **The 991 route is untagged** (per AVX-71737) so it applies to GKE-managed nodes that don't carry the legacy `avx-snat-noip` tag.
- **GKE master authorized networks must include the Aviatrix spoke GW egress IP.** The `clusters/*` layer appends it automatically. When `enable_aviatrix_onboarding=true` and `master_authorized_cidr_blocks` is restrictive, also set `aviatrix_controller_public_ip` so the controller can reach the master endpoint during onboarding.
