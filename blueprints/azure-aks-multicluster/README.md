# Multi-Cluster AKS with Aviatrix Transit Architecture

This blueprint deploys a multi-cluster Kubernetes environment on Azure with Aviatrix transit networking, demonstrating Distributed Cloud Firewall (DCF) for Kubernetes capabilities.

> [!TIP]
> **Optimized for Claude Code** — Run `/deploy-blueprint` for AI-guided deployment with prerequisite checks and automated orchestration, or `/analyze-blueprint` for resource and cost details. [Get Claude Code](https://claude.ai/code)

---

## Prerequisites

Before deploying this infrastructure, ensure you have the following prerequisites in place.

### Aviatrix Infrastructure

| Component | Requirement | Notes |
|-----------|-------------|-------|
| **Aviatrix Controller** | Version compatible with provider ~> 8.2 | Must be deployed and accessible |
| **Aviatrix CoPilot** | Recommended | Required for DCF visualization and SmartGroups UI |
| **Azure Account Onboarded** | Account registered in Controller | Use the exact account name in `terraform.tfvars` |

### Local Tools

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.5 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure provisioning |
| **Azure CLI** | Latest | [Install Guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) | Azure authentication and AKS kubectl auth |
| **kubectl** | Latest | [Install Guide](https://kubernetes.io/docs/tasks/tools/) | Kubernetes cluster interaction |
| **Helm** | >= 3.x | [Install Guide](https://helm.sh/docs/intro/install/) | Kubernetes package management (used by Terraform Helm provider) |

### Azure Service Principal Permissions

The Azure service principal used must have permissions to create and manage:

- **AKS**: Clusters, node pools, managed identities, OIDC issuers
- **Virtual Network**: VNets, subnets, route tables, UDRs, network security groups
- **Application Gateway**: Standard_v2 gateways, public IP addresses
- **Role Assignments**: Managed identity role assignments (Network Contributor, route table permissions)
- **Private DNS**: Private DNS zones, virtual network links, record sets
- **Compute**: Virtual machines (DB test VM), managed disks

The built-in **Contributor** role at the subscription scope is sufficient for a lab environment. For production, scope permissions to the target resource group.

### Azure Subscription Quotas

This blueprint deploys 9 VMs across two vCPU families. **Default subscription quota of 10 regional vCPUs is not enough.** Verify and request increases before deploying:

| Quota | Used by blueprint | Recommended limit |
|-------|-------------------|-------------------|
| **Total Regional vCPUs** | 17 (transit + 3 spoke GWs + 4 AKS nodes + DB VM) | **≥ 30** |
| **Standard DSv3 Family vCPUs** | 8 (4 Aviatrix gateways × 2 vCPU each) | ≥ 16 |
| **Standard BS Family vCPUs** | 9 (4 AKS nodes × 2 vCPU + DB VM × 1 vCPU) | ≥ 16 |
| **Standard Public IP Addresses** | 2 (one per Application Gateway) | default sufficient |

Check current usage and limits:
```bash
az vm list-usage -l eastus2 -o table | grep -E "Total Regional|Standard DSv3|Standard BS Family"
```

Request a quota increase via Azure Portal (Subscriptions → Usage + quotas → Request increase) or programmatically:
```bash
TOKEN=$(az account get-access-token --query accessToken -o tsv)
curl -X PATCH \
  "https://management.azure.com/subscriptions/<SUB_ID>/providers/Microsoft.Compute/locations/eastus2/providers/Microsoft.Quota/quotas/cores?api-version=2023-02-01" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"properties":{"limit":{"limitObjectType":"LimitValue","value":30},"name":{"value":"cores"}}}'
```
Increases to ≤ 30 vCPUs are typically auto-approved within a few minutes.

#### Azure Region Naming

The Aviatrix provider and the Azure provider use different region name formats. Both must be specified:

| Variable | Format | Example |
|----------|--------|---------|
| `azure_region` | azurerm lowercase | `eastus2` |
| `aviatrix_azure_region` | Aviatrix display name | `East US 2` |

---

## Architecture Overview

```
Internet
   │
   ▼
┌──────────────────────────────────────────────────────────────────┐
│  Azure Application Gateways (Standard_v2)                        │
│  frontend-appgw (172.x.x.x:80)   backend-appgw (52.x.x.x:80)   │
│  Layer 7 reverse proxy — terminates TCP, no asymmetric routing   │
└─────────────────┬──────────────────────────┬─────────────────────┘
                  │                          │
         ┌────────▼────────┐       ┌─────────▼───────┐
         │  Frontend VNet  │       │  Backend VNet    │
         │  10.10.0.0/23   │       │  10.20.0.0/23   │
         │                 │       │                  │
         │ NGINX LB        │       │ NGINX LB         │
         │ 10.10.0.200     │       │ 10.20.0.200      │
         │    │            │       │    │             │
         │ AKS frontend    │       │ AKS backend      │
         │ (Cilium CNI)    │       │ (Cilium CNI)     │
         │ pod: 100.64/16  │       │ pod: 100.64/16   │
         │                 │       │                  │
         │ Aviatrix Spoke  │       │ Aviatrix Spoke   │
         │ Gateway         │       │ Gateway          │
         └────────┬────────┘       └────────┬─────────┘
                  │  Aviatrix Transit Fabric  │
                  └──────────┬───────────────┘
                             │
              ┌──────────────▼──────────────┐
              │  Aviatrix Transit Gateway    │
              │  Transit VNet 10.2.0.0/20   │
              └──────────────┬──────────────┘
                             │
              ┌──────────────▼──────────────┐
              │  DB Spoke VNet 10.5.0.0/22  │
              │  Linux test VM              │
              │  db.azure.aviatrixdemo.local │
              └─────────────────────────────┘
```

### Why Application Gateway Instead of a Public Load Balancer

AKS clusters are configured with `outbound_type = "userDefinedRouting"` — all egress from node and system subnets flows through a `0.0.0.0/0 → VirtualAppliance (Aviatrix Spoke GW)` UDR. A public Azure Load Balancer (Layer 4) causes asymmetric routing: internet traffic arrives at the LB, but return traffic from pods exits through the UDR and arrives at the client from the Aviatrix GW IP — not the LB IP — so TCP drops it.

Azure Application Gateway (Layer 7) terminates the TCP connection and opens a new one to the NGINX internal LB. All response traffic is VNet-internal (AppGW → NGINX → AppGW → client) and never touches the UDR. No asymmetric routing.

### Traffic Flow (Internet → Gatus)

```
Internet client
  → AppGW public IP :80
  → NGINX internal LB (10.x.0.200) :80        [VNet-internal, no UDR]
  → Gatus pod :8080                            [VNet-internal, no UDR]
  ← response back to AppGW                    [VNet-internal, no UDR]
  ← AppGW sends response to internet client
```

### Pod Networking (Cilium Overlay)

Both clusters use **Azure CNI Powered by Cilium** with an RFC 6598 overlay CIDR (`100.64.0.0/16`) for pod IPs. This CIDR is the same across both clusters — overlapping by design. Aviatrix spoke gateways SNAT pod IPs to the spoke GW private IP before forwarding to transit, allowing the overlapping pod CIDRs to coexist without routing conflicts.

---

## Directory Structure

```
azure-aks-multicluster/
├── network/                    # Layer 1: Network foundation
│   ├── main.tf                 # Transit, spoke GWs, VNets, AppGWs, DB VM, DNS zone
│   ├── variables.tf
│   ├── outputs.tf              # VNet IDs, subnet IDs, AppGW IPs, NGINX LB IPs
│   ├── versions.tf
│   └── modules/
│       ├── aks-vnet/           # VNet + subnet module (nodes, system, Aviatrix GW subnets)
│       └── linux-vm/           # Linux test VM module (DB spoke)
│
├── clusters/
│   ├── frontend/               # Layer 2: Frontend AKS control plane
│   │   ├── main.tf             # AKS cluster, managed identities, role assignments, OIDC
│   │   ├── data.tf             # Read network state
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   │
│   └── backend/                # Layer 2: Backend AKS control plane (parallel)
│
├── nodes/
│   ├── frontend/               # Layer 3: Frontend node pool and Helm add-ons
│   │   ├── main.tf             # Node pool configuration
│   │   ├── helm.tf             # NGINX Ingress, ExternalDNS, Aviatrix k8s-firewall
│   │   ├── data.tf             # Read network + cluster state
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   │
│   └── backend/                # Layer 3: Backend node pool and Helm add-ons (parallel)
│
├── k8s-apps/                   # Layer 4: Kubernetes application manifests (kubectl apply)
│   ├── frontend/               # Gatus health dashboard — Frontend cluster
│   │   └── gatus.yaml
│   ├── backend/                # Gatus health dashboard — Backend cluster
│   │   └── gatus.yaml
│   └── dcf-crd/                # DCF Kubernetes CRD policy examples
│       ├── firewallpolicy-infosec.yaml
│       └── webgrouppolicy-dev.yaml
│
└── terraform.tfvars.example    # Variable reference with deployment instructions
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

Each layer reads the previous layer's state via `data "terraform_remote_state" "local"` data sources. All state is local — no remote backend is used.

---

## Complete Deployment Guide

> **Note:** Complete all items in the [Prerequisites](#prerequisites) section before proceeding.

### Step 1: Set Environment Variables

```bash
# Aviatrix Controller credentials
export AVIATRIX_CONTROLLER_IP="<controller-ip>"
export AVIATRIX_USERNAME="<username>"
export AVIATRIX_PASSWORD="<password>"

# Azure Service Principal credentials
export ARM_SUBSCRIPTION_ID="<subscription-id>"
export ARM_TENANT_ID="<tenant-id>"
export ARM_CLIENT_ID="<client-id>"
export ARM_CLIENT_SECRET="<client-secret>"

# Verify Azure access
az account show
```

### Step 2: Deploy Network Infrastructure

The network layer creates the Aviatrix transit/spoke topology, VNets with subnets and UDRs, Application Gateways, Azure Private DNS zone, and the DB test VM.

```bash
cd network/

# Initialize Terraform
terraform init -upgrade

# Create your variable file
cp ../terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set at minimum:
#   name_prefix                 (e.g., "aks-demo")
#   aviatrix_azure_account_name (your Azure account name in Aviatrix Controller)
#   azure_region                (e.g., "eastus2")
#   aviatrix_azure_region       (e.g., "East US 2")
vim terraform.tfvars

# Deploy network infrastructure (~15-20 minutes)
# AppGW provisioning takes ~7 minutes
terraform apply
```

**What's created:**
- Aviatrix Transit Gateway (transit VNet `10.2.0.0/20`, FireNet-enabled)
- Frontend VNet (`10.10.0.0/23`) with Aviatrix spoke gateway and UDR
- Backend VNet (`10.20.0.0/23`) with Aviatrix spoke gateway and UDR
- DB spoke VNet (`10.5.0.0/22`) with Linux test VM (Apache)
- Frontend Application Gateway (Standard_v2, public IP, backends to `10.10.0.200`)
- Backend Application Gateway (Standard_v2, public IP, backends to `10.20.0.200`)
- Azure Private DNS zone (`azure.aviatrixdemo.local`) linked to all VNets
- Static DNS A record `db.azure.aviatrixdemo.local` → DB VM IP
- DCF SmartGroups, WebGroups, and firewall policy ruleset

> **AppGW backend health:** After the network apply, the Application Gateway backends will show as **Unhealthy** until Step 5 (nodes) configures NGINX on the static IP. This is expected.

### Step 3: Deploy Frontend AKS Cluster

The cluster layer creates the AKS control plane, user-assigned managed identities, Workload Identity federation for ExternalDNS, and the necessary role assignments for UDR management.

```bash
cd ../clusters/frontend/

# Initialize Terraform
terraform init

# Create variable file (copy from network, same values apply)
cp ../../terraform.tfvars.example terraform.tfvars
# Verify or adjust:
#   azure_region        (default: eastus2)
#   kubernetes_version  (default: 1.32)
#   authorized_ip_ranges (add your IP: run "curl -s ifconfig.me")
vim terraform.tfvars

# Deploy cluster (~10-15 minutes)
terraform apply
```

**What's created:**
- AKS cluster (Azure CNI Powered by Cilium, `outbound_type = "userDefinedRouting"`)
- System node pool (initial sizing; replaced by managed pool in Layer 3)
- User-assigned managed identity for AKS cluster
- User-assigned managed identity for ExternalDNS (Workload Identity)
- Federated credential for ExternalDNS Workload Identity
- Role assignments: Network Contributor on frontend VNet, route table write access
- OIDC issuer enabled for Workload Identity

### Step 4: Deploy Backend AKS Cluster (Parallel with Step 3)

```bash
cd ../backend/

# Initialize Terraform
terraform init

# Deploy cluster (~10-15 minutes)
terraform apply
```

**What's created:** Same as the frontend cluster, scoped to the backend VNet.

Steps 3 and 4 can run in parallel in separate terminals.

### Step 5: Deploy Frontend Helm Add-ons

The node layer installs Helm charts: NGINX Ingress Controller (internal LB at static IP `10.10.0.200`), ExternalDNS (Azure Private DNS), and Aviatrix k8s-firewall (DCF CRDs). The default node pool from Step 3 is the only AKS node pool — there is no separate user node pool.

```bash
cd ../../nodes/frontend/

# Initialize Terraform
terraform init

# Deploy Helm charts (~3-5 minutes)
terraform apply
```

**What's created:**
- NGINX Ingress Controller — internal Azure LB at `10.10.0.200` in the `frontend-system` subnet
- ExternalDNS — creates Private DNS A records for annotated Services and Ingresses
- Aviatrix k8s-firewall — installs `FirewallPolicy` and `WebgroupPolicy` CRDs

After this step, the frontend AppGW backend probe will become **Healthy** within ~60 seconds.

### Step 6: Deploy Backend Helm Add-ons (Parallel with Step 5)

```bash
cd ../backend/

# Initialize Terraform
terraform init

# Deploy node pool and Helm charts (~7-10 minutes)
terraform apply
```

**What's created:** Same Helm add-ons as the frontend, with NGINX at `10.20.0.200` in the `backend-system` subnet.

Steps 5 and 6 can run in parallel in separate terminals.

### Step 7: Configure kubectl for Both Clusters

```bash
# Frontend cluster
az aks get-credentials \
  --resource-group <name_prefix>-frontend-rg \
  --name <name_prefix>-frontend \
  --context frontend \
  --overwrite-existing

# Backend cluster
az aks get-credentials \
  --resource-group <name_prefix>-backend-rg \
  --name <name_prefix>-backend \
  --context backend \
  --overwrite-existing

# Verify both clusters are reachable
kubectl get nodes --context frontend
kubectl get nodes --context backend
```

**Expected output:**
```
NAME                             STATUS   ROLES    AGE   VERSION
aks-system-35398034-vmss000001   Ready    <none>   10m   v1.32.x
```

You can also retrieve the exact command from Terraform output:
```bash
cd clusters/frontend/
terraform output kubectl_config_command
```

**Verify NGINX is on the internal LB (not a public IP):**
```bash
kubectl get svc -n ingress-nginx --context frontend
# EXTERNAL-IP should be 10.10.0.200

kubectl get svc -n ingress-nginx --context backend
# EXTERNAL-IP should be 10.20.0.200
```

**Verify AppGW backend health:**
```bash
az network application-gateway show-backend-health \
  --resource-group <name_prefix>-frontend-rg \
  --name <name_prefix>-frontend-appgw \
  --query "backendAddressPools[0].backendHttpSettingsCollection[0].servers[0].health" -o tsv
# Expected: Healthy
```

**Verify DCF CRDs are installed:**
```bash
kubectl get crd firewallpolicies.networking.aviatrix.com --context frontend
kubectl get crd webgrouppolicies.networking.aviatrix.com --context frontend
```

### Step 8: Deploy Gatus Monitoring Dashboards

Gatus is deployed as a Kubernetes manifest (not Terraform-managed), applied directly with kubectl.

```bash
# Frontend cluster
kubectl apply -f k8s-apps/frontend/gatus.yaml --context frontend

# Backend cluster
kubectl apply -f k8s-apps/backend/gatus.yaml --context backend

# Verify pods are running
kubectl get pods -n gatus --context frontend
kubectl get pods -n gatus --context backend
```

**Expected output (both clusters):**
```
NAME                       READY   STATUS    RESTARTS   AGE
frontend-776574778b-8ptph   1/1     Running   0          60s
frontend-776574778b-x6ccv   1/1     Running   0          60s
```

**Get the Application Gateway public IPs to access Gatus:**
```bash
cd network/
terraform output frontend_appgw_public_ip
terraform output backend_appgw_public_ip
```

Open `http://<frontend_appgw_public_ip>/` and `http://<backend_appgw_public_ip>/` in a browser. Each shows a Gatus dashboard titled "Frontend Cluster" or "Backend Cluster" respectively.

---

## Test Scenarios

### Scenario 1: Internet Access via Application Gateway

Verify the AppGW → NGINX → Gatus path is working end-to-end.

```bash
# Get AppGW public IPs
FRONTEND_IP=$(cd network/ && terraform output -raw frontend_appgw_public_ip)
BACKEND_IP=$(cd network/ && terraform output -raw backend_appgw_public_ip)

# Test HTTP response
curl -s -o /dev/null -w "%{http_code}" http://$FRONTEND_IP/
# Expected: 200

curl -s -o /dev/null -w "%{http_code}" http://$BACKEND_IP/
# Expected: 200
```

### Scenario 2: East-West Connectivity (Cross-Cluster via Aviatrix Transit)

Gatus on each cluster monitors the other cluster's service over port 8080. Verify these endpoints show green in the Gatus dashboard.

**Frontend Gatus monitors:**
- `http://db.azure.aviatrixdemo.local` (DB VM in DB spoke)
- `http://backend.azure.aviatrixdemo.local:8080` (Gatus in backend cluster)

**Backend Gatus monitors:**
- `http://db.azure.aviatrixdemo.local` (DB VM in DB spoke)
- `http://frontend.azure.aviatrixdemo.local:8080` (Gatus in frontend cluster)

You can also test manually:
```bash
# From a debug pod in the frontend cluster, reach the backend service
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never \
  --context frontend -- curl -s http://backend.azure.aviatrixdemo.local:8080/health
# Expected: HTTP 200
```

### Scenario 3: DCF Egress Policy — Allowed Domains

Gatus monitors several allowed egress endpoints. Verify these show green:

- `https://kubernetes.io` (kubernetes_io WebGroup)
- `https://github.com/AviatrixSystems/terraform-provider-aviatrix` (github_aviatrix WebGroup)
- `https://registry.npmjs.org` (npm_registry WebGroup)

### Scenario 4: DCF Threat Blocking — GeoBlock and ThreatIQ

Gatus monitors two threat endpoints that **should be blocked** by DCF. They appear as red/failed in the dashboard, which is the correct behavior:

- `icmp://www.irna.ir` — GeoBlock (Iran)
- `icmp://102.130.117.167` — ThreatGuard feed IP

> **Note:** The threat IP `102.130.117.167` must be present in your active Aviatrix ThreatGuard feed for blocking to work. If your feed differs, verify and update the IP in `k8s-apps/frontend/gatus.yaml` and `k8s-apps/backend/gatus.yaml`.

### Scenario 5: DCF CRD-Based Policies

Apply example CRD policies to test Kubernetes-native policy management:

```bash
# Apply the InfoSec namespace FirewallPolicy (allows VirusTotal access for pods labeled app=infosec)
kubectl apply -f k8s-apps/dcf-crd/firewallpolicy-infosec.yaml --context frontend

# Apply the Dev namespace WebGroupPolicy (allows broader package registry access for dev pods)
kubectl apply -f k8s-apps/dcf-crd/webgrouppolicy-dev.yaml --context frontend

# Verify policies are accepted
kubectl get firewallpolicies -n gatus --context frontend
kubectl get webgrouppolicies -n dev --context frontend
```

### Scenario 6: Private DNS Resolution

ExternalDNS creates Private DNS records for Gatus Services and Ingresses. Verify DNS resolution works across clusters:

```bash
# From a debug pod in the frontend cluster, resolve the backend DNS name
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never \
  --context frontend -- nslookup backend.azure.aviatrixdemo.local
# Expected: resolves to 10.20.x.x (backend NGINX LB IP)

# Verify ExternalDNS created the records
az network private-dns record-set list \
  --resource-group <name_prefix>-shared-rg \
  --zone-name azure.aviatrixdemo.local \
  --output table
```

---

## How It Works

### Azure CNI Powered by Cilium

Both clusters use Azure CNI Powered by Cilium with a Cilium overlay pod CIDR (`100.64.0.0/16`, RFC 6598). This is different from the AWS EKS blueprint which uses VPC CNI with ENIConfig for secondary CIDR pod networking.

Key differences from standard AKS networking:
- Pod IPs (`100.64.x.x`) are **not routable** in the Azure VNet — they exist only in the Cilium overlay
- `outbound_type = "userDefinedRouting"` routes all egress through the Aviatrix spoke gateway UDR
- `single_ip_snat = true` on spoke gateways SNATs all pod traffic (including `100.64.x.x`) to the spoke GW private IP before forwarding to transit
- Azure does **not** expose a `cilium-config` ConfigMap for this managed mode — Cilium is fully Azure-managed, so no additional Cilium configuration is required in Terraform

**Pod traffic flow (cross-cluster):**
```
Frontend Pod (100.64.x.x)
  → frontend-system subnet
  → UDR: 0.0.0.0/0 → Frontend Aviatrix Spoke GW
  → Spoke GW SNATs 100.64.x.x → 10.10.0.4 (spoke GW private IP)
  → Aviatrix Transit
  → Backend Aviatrix Spoke GW
  → Backend service/LB (10.20.x.x)
  → Backend Pod (100.64.y.y)
```

**Why pod CIDR is excluded from transit advertisements:**
The transit gateway is configured with `excluded_advertised_spoke_routes = "100.64.0.0/16"`. Since both clusters use the same pod CIDR, advertising it from both spokes would create an ambiguous route. The SNAT on each spoke GW ensures transit only sees the unique spoke GW IP as the source.

### Workload Identity (vs. IRSA on EKS)

Instead of AWS IRSA (IAM Roles for Service Accounts), Azure uses Workload Identity with OIDC federation. Terraform creates:
1. A user-assigned managed identity for ExternalDNS
2. A federated credential linking the identity to the AKS OIDC issuer and the `external-dns` Kubernetes ServiceAccount
3. A role assignment granting the identity Private DNS Zone Contributor on the DNS zone

No credentials are stored in the cluster. The `azure.json` file mounted by ExternalDNS uses `useWorkloadIdentityExtension: true`.

### Application Gateway + NGINX Internal LB Pattern

The blueprint avoids asymmetric routing caused by the Aviatrix UDR through a two-tier ingress architecture:

| Component | Type | IP | Purpose |
|-----------|------|----|---------|
| Application Gateway | Internet-facing, Layer 7 | Public (dynamic) | Terminates internet TCP connections |
| NGINX Ingress Controller | Internal, Layer 7 | Private, static (`10.x.0.200`) | Kubernetes ingress routing |

The AppGW subnet (`10.x.0.64/26`) intentionally has **no UDR associated**. AppGW management traffic (GatewayManager service tag, ports 65200–65535) must reach the Azure platform directly. Attaching the Aviatrix UDR to the AppGW subnet breaks AppGW provisioning.

### Aviatrix Distributed Cloud Firewall (DCF)

The network layer provisions a complete DCF policy ruleset. Policies are enforced at the spoke gateways — DCF inspects the original pod source IPs (pre-SNAT) for inbound traffic decisions.

**SmartGroups:**

| Name | Type | Selector |
|------|------|----------|
| `frontend-vnet` | CIDR | `10.10.0.0/23` |
| `backend-vnet` | CIDR | `10.20.0.0/23` |
| `db-vnet` | CIDR | `10.5.0.0/22` |
| `all-aks-clusters` | CIDR union | Both AKS VNets |
| `frontend-service` | Hostname | `frontend.azure.aviatrixdemo.local` |
| `backend-service` | Hostname | `backend.azure.aviatrixdemo.local` |
| `database` | Hostname | `db.azure.aviatrixdemo.local` |
| `geo-blocked` | Geo feed | Country: Iran |
| `threat-intel` | Threat feed | Aviatrix ThreatGuard |

**WebGroups (domain-based egress filtering):**

| Name | Domains |
|------|---------|
| `azure-required` | `*.microsoft.com`, `*.azure.com`, `*.azurecr.io`, `mcr.microsoft.com`, `*.blob.core.windows.net`, `*.azmk8s.io`, Ubuntu/Debian repos, and more |
| `kubernetes-io` | `kubernetes.io`, `*.kubernetes.io` |
| `docker-hub` | `registry-1.docker.io`, `*.docker.io`, `auth.docker.io` |
| `npm-registry` | `registry.npmjs.org`, `*.npmjs.org` |
| `github-aviatrix` | `github.com/AviatrixSystems/*`, `api.github.com` |

**DCF Rule Priority Summary:**

| Priority | Rule | Action |
|----------|------|--------|
| 0 | Block geo-blocked sources | Deny |
| 1 | Block ThreatGuard IPs | Deny |
| 10–15 | East-west TCP (port 8080) between clusters and DB | Permit |
| 20 | AKS-required HTTPS egress (azure-required + kubernetes-io + docker-hub) | Permit |
| 21 | AKS-required HTTP egress (Ubuntu/Debian apt repos) | Permit |
| 30–33 | Additional egress: npm, GitHub Aviatrix paths | Permit |
| 50–99 | Reserved for Aviatrix k8s-firewall CRD-injected rules | Dynamic |

### Kubernetes CRD-Based Firewall Policies

The Aviatrix k8s-firewall Helm chart installs two CRDs in each cluster:

- `firewallpolicies.networking.aviatrix.com` — define per-pod firewall rules using label selectors
- `webgrouppolicies.networking.aviatrix.com` — define domain-based filtering for labeled pods

These CRDs allow application teams to manage DCF policies as Kubernetes resources, without Terraform access. Policies are synced to Aviatrix SmartGroups and WebGroups automatically by the k8s-firewall controller.

**Example: Allow infosec pods to reach VirusTotal**
```bash
kubectl apply -f k8s-apps/dcf-crd/firewallpolicy-infosec.yaml --context frontend
kubectl get firewallpolicies -n gatus --context frontend
```

**Example: Allow dev namespace pods to reach additional package registries**
```bash
kubectl apply -f k8s-apps/dcf-crd/webgrouppolicy-dev.yaml --context frontend
kubectl get webgrouppolicies -n dev --context frontend
```

---

## Day 2 Operations

### Scale Node Pool

```bash
cd nodes/frontend/

# Edit terraform.tfvars — adjust min_count, max_count, node_count
vim terraform.tfvars

# Apply changes (~2-3 minutes)
terraform apply
```

### Upgrade Kubernetes Version

Upgrade the control plane first, then the node pool:

```bash
# Step 1: Upgrade control plane
cd clusters/frontend/
vim terraform.tfvars  # Update kubernetes_version
terraform apply

# Step 2: Upgrade node pool
cd ../../nodes/frontend/
terraform apply
# Terraform runs a rolling node replacement
```

### Add an Additional DNS Record

ExternalDNS manages records automatically via annotations. For a manual static record:
```bash
az network private-dns record-set a add-record \
  --resource-group <name_prefix>-shared-rg \
  --zone-name azure.aviatrixdemo.local \
  --record-set-name myservice \
  --ipv4-address 10.10.0.100
```

---

## Destroy Instructions

Always destroy in **reverse order**. Kubernetes resources (ingresses, services) must be deleted first so that ExternalDNS can clean up Private DNS records before Terraform removes the DNS zone.

### Step 1: Delete Kubernetes Resources

```bash
# Frontend cluster
kubectl delete ingress --all -A --context frontend
kubectl delete svc -A --field-selector spec.type=LoadBalancer --context frontend

# Backend cluster
kubectl delete ingress --all -A --context backend
kubectl delete svc -A --field-selector spec.type=LoadBalancer --context backend

# Wait ~60s for ExternalDNS to remove DNS records
sleep 60

# Verify DNS records are cleaned up (only db.* should remain as a Terraform-managed record)
az network private-dns record-set list \
  --resource-group <name_prefix>-shared-rg \
  --zone-name azure.aviatrixdemo.local \
  --output table
```

### Step 2: Destroy Node Pools (Parallel)

```bash
# Terminal 1
cd nodes/frontend/ && terraform destroy

# Terminal 2
cd nodes/backend/ && terraform destroy
```

### Step 3: Destroy AKS Clusters (Parallel)

```bash
# Terminal 1
cd clusters/frontend/ && terraform destroy

# Terminal 2
cd clusters/backend/ && terraform destroy
```

### Step 4: Destroy Network Layer

```bash
cd network/ && terraform destroy
```

### Step 5: Clean Up kubectl Contexts (Optional)

```bash
kubectl config delete-context frontend
kubectl config delete-context backend
```

---

## Troubleshooting

### Pods Can't Reach Other Clusters

1. **Check SNAT configuration** in Aviatrix Controller → Gateways → select spoke gateway → Source NAT. Verify `100.64.0.0/16` SNAT entry exists.

2. **Verify the UDR has a route for 0.0.0.0/0:**
   ```bash
   az network route-table show \
     --resource-group <name_prefix>-frontend-rg \
     --name <name_prefix>-frontend-udr \
     --query "routes" -o table
   ```

3. **Test DNS resolution from inside the cluster:**
   ```bash
   kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never \
     --context frontend -- nslookup backend.azure.aviatrixdemo.local
   ```

4. **Check Aviatrix spoke gateway connectivity** in CoPilot → Topology, verify both spokes are connected to transit.

### AppGW Backend Shows Unhealthy

The AppGW health probe checks `GET /health HTTP/1.1 Host: health.local` → NGINX → Gatus `/health`.

1. **Verify NGINX is running with the correct internal LB IP:**
   ```bash
   kubectl get svc -n ingress-nginx --context frontend
   # EXTERNAL-IP must be 10.10.0.200, not a public IP or <pending>
   ```

2. **Verify the Gatus ingress is bound:**
   ```bash
   kubectl get ingress -n gatus --context frontend
   # ADDRESS should be 10.10.0.200
   ```

3. **Verify Gatus pods are healthy:**
   ```bash
   kubectl get pods -n gatus --context frontend
   # All pods should be 1/1 Running
   ```

4. **Check NGINX is routing `/health` correctly:**
   ```bash
   kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never \
     --context frontend -- curl -s http://10.10.0.200/health
   # Expected: 200 OK
   ```

5. **Check AppGW backend health detail:**
   ```bash
   az network application-gateway show-backend-health \
     --resource-group <name_prefix>-frontend-rg \
     --name <name_prefix>-frontend-appgw \
     --output json
   ```

### NGINX Ingress Stuck in Pending (No IP Assigned)

If the NGINX ingress controller Service shows `<pending>` for EXTERNAL-IP instead of `10.10.0.200`:

1. **Check AKS has permission to create internal LBs in the system subnet:**
   ```bash
   az role assignment list \
     --assignee <aks-managed-identity-principal-id> \
     --scope /subscriptions/<sub-id>/resourceGroups/<name_prefix>-frontend-rg \
     --output table
   # Should include Network Contributor
   ```

2. **Check the NGINX controller pod logs:**
   ```bash
   kubectl logs -n ingress-nginx \
     -l app.kubernetes.io/name=ingress-nginx --context frontend --tail=20
   ```

3. **Verify the subnet name matches the annotation** (`frontend-system`). The subnet must exist in the AKS VNet.

### ExternalDNS Not Creating DNS Records

1. **Check ExternalDNS logs:**
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns \
     --context frontend --tail=20
   ```

2. **Verify Workload Identity is configured correctly:**
   ```bash
   kubectl describe sa external-dns -n kube-system --context frontend
   # Annotations should include azure.workload.identity/client-id
   ```

3. **Verify the `azure.json` secret is mounted:**
   ```bash
   kubectl get secret -n kube-system --context frontend | grep azure
   ```

### AppGW Provisioning Fails or Times Out

If `terraform apply` on the network layer fails with AppGW-related errors:

1. **Do not associate the Aviatrix UDR with the AppGW subnet.** The AppGW subnet (`frontend-appgw`, `backend-appgw`) must have no route table. Associating the `0.0.0.0/0 → VirtualAppliance` UDR breaks AppGW management plane traffic.

2. **Verify the AppGW subnet does not overlap** with the Aviatrix GW subnet (`10.x.0.0/28`) or the system subnet (`10.x.0.128/25`). AppGW uses `10.x.0.64/26`.

3. **Check subscription quota** for Standard_v2 Application Gateways in the region.

### Terraform Remote State Errors

If a layer fails with `No such file or directory` for a state file:

```
Error: Failed to read state file
path = "../../network/terraform.tfstate"
```

Ensure the previous layer has been successfully applied and its `terraform.tfstate` exists:
```bash
ls -la network/terraform.tfstate
ls -la clusters/frontend/terraform.tfstate
```

---

## Resource Inventory

### Compute Resources

| Component | Resource Type | Qty | VM Size | Notes |
|-----------|--------------|-----|---------|-------|
| **Aviatrix Gateways** | | | | |
| Transit Gateway | Azure VM | 1 | Standard_D2s_v3 | No HA, FireNet OFF |
| Frontend Spoke GW | Azure VM | 1 | Standard_D2s_v3 | Single IP SNAT, no HA |
| Backend Spoke GW | Azure VM | 1 | Standard_D2s_v3 | Single IP SNAT, no HA |
| DB Spoke GW | Azure VM | 1 | Standard_D2s_v3 | Single IP SNAT, no HA |
| **AKS Clusters** | | | | |
| Frontend Control Plane | AKS | 1 | — | K8s 1.33, Free tier |
| Backend Control Plane | AKS | 1 | — | K8s 1.33, Free tier |
| **AKS Node Pools** | | | | |
| Frontend Node Pool | Azure VMSS | 2 (desired) | Standard_B2s | min=1, max=3 |
| Backend Node Pool | Azure VMSS | 2 (desired) | Standard_B2s | min=1, max=3 |
| **Test VM** | | | | |
| DB Linux VM | Azure VM | 1 | Standard_B1s | DB spoke, Apache |

**Total VMs (at desired state):** 10

### Networking Resources

| Component | Qty | Details |
|-----------|-----|---------|
| Virtual Networks | 4 | Transit (`10.2.0.0/20`), Frontend (`10.10.0.0/23`), Backend (`10.20.0.0/23`), DB (`10.5.0.0/22`) |
| Subnets | 14+ | Aviatrix GW (/28), AppGW (/26), System (/25), Nodes (/24) per AKS VNet; GW + VMs in DB VNet |
| Route Tables (UDR) | 3 | Frontend (nodes + system subnets), Backend (nodes + system subnets), DB |
| Application Gateways | 2 | Standard_v2, one per AKS VNet |
| Public IPs | 2 | Standard SKU Static, one per AppGW |
| Internal Load Balancers | 2 | Standard, NGINX Ingress Controller (managed by AKS) |
| Private DNS Zone | 1 | `azure.aviatrixdemo.local` |
| DNS Zone VNet Links | 4 | Linked to all VNets for resolution |
| Static DNS Records | 1 | `db.azure.aviatrixdemo.local` → DB VM IP |

### Subnet Layout (per AKS VNet, example: Frontend `10.10.0.0/23`)

| Subnet Name | CIDR | Size | Purpose | UDR |
|-------------|------|------|---------|-----|
| `frontend-avx-gw` | `10.10.0.0/28` | 16 IPs | Aviatrix spoke gateway | No |
| `frontend-appgw` | `10.10.0.64/26` | 64 IPs | Application Gateway | **No** (required) |
| `frontend-system` | `10.10.0.128/25` | 128 IPs | NGINX internal LB, system pods | Yes |
| `frontend-nodes` | `10.10.1.0/24` | 256 IPs | AKS node VMs | Yes |

---

## Monthly Cost Estimate (East US 2, Pay-as-you-go)

> Prices are pay-as-you-go rates as of March 2026. Actual costs vary with traffic, autoscaling, and reserved instance discounts (up to 40% savings with 1-year reservations). Aviatrix licensing is billed separately and is not included below.

### Compute

| Resource | VM Size | Qty | Hourly Rate | Monthly (730 hrs) |
|----------|---------|-----|-------------|-------------------|
| Aviatrix Transit GW | Standard_D2s_v3 | 1 | $0.0960 | $70.08 |
| Aviatrix Frontend Spoke GW | Standard_D2s_v3 | 1 | $0.0960 | $70.08 |
| Aviatrix Backend Spoke GW | Standard_D2s_v3 | 1 | $0.0960 | $70.08 |
| Aviatrix DB Spoke GW | Standard_D2s_v3 | 1 | $0.0960 | $70.08 |
| AKS Frontend Nodes | Standard_B2s | 2 | $0.0416 each | $60.74 |
| AKS Backend Nodes | Standard_B2s | 2 | $0.0416 each | $60.74 |
| DB Test VM | Standard_B1s | 1 | $0.0124 | $9.05 |
| **Subtotal Compute** | | | | **$410.85** |

> **Family-quota choice:** Aviatrix gateways use `Standard_D2s_v3` (DSv3 family) and AKS nodes use `Standard_B2s` (BS family). This deliberate split avoids one family saturating at the default 10-vCPU subscription quota. See [Azure Subscription Quotas](#azure-subscription-quotas).

### AKS Control Plane

| Resource | Tier | Qty | Monthly |
|----------|------|-----|---------|
| Frontend AKS Control Plane | Free | 1 | $0.00 |
| Backend AKS Control Plane | Free | 1 | $0.00 |
| **Subtotal AKS Control Plane** | | | **$0.00** |

> If you upgrade to Standard tier (SLA-backed): $73.00/cluster/month × 2 = **$146.00/month** additional.

### Application Gateways

| Component | Rate | Qty | Monthly |
|-----------|------|-----|---------|
| Standard_v2 fixed rate | $0.246/hr | 2 | $359.16 |
| Capacity Units (variable, ~1 CU at lab traffic) | $0.008/CU/hr | 2 × 1 CU | $11.68 |
| **Subtotal Application Gateways** | | | **~$370.84** |

> At higher traffic loads, 1 CU per AppGW is a minimum. Production workloads may consume 2–10 CUs per AppGW, adding $11–$58 per AppGW per month in variable costs.

### Networking

| Resource | Rate | Qty | Monthly |
|----------|------|-----|---------|
| Public IP (Standard Static) | $0.005/hr | 2 | $7.30 |
| Internal Standard LB (NGINX, ≤5 rules) | $0.025/hr | 2 | $36.50 |
| Private DNS Zone | $0.50/zone | 1 | $0.50 |
| Private DNS Queries | ~$0.40/1M | ~1M | ~$0.40 |
| VNets, Subnets, UDRs | Free | — | $0.00 |
| **Subtotal Networking** | | | **~$44.70** |

### Storage

| Resource | Type | Qty | Monthly |
|----------|------|-----|---------|
| AKS Node OS Disks (P10, 128 GiB, LRS) | Premium SSD | 4 | $78.84 |
| DB VM OS Disk (P6, 64 GiB, LRS) | Premium SSD | 1 | ~$9.87 |
| **Subtotal Storage** | | | **~$88.71** |

### Data Transfer (Estimated)

| Type | Est. Volume | Rate | Monthly |
|------|-------------|------|---------|
| Cross-VNet via Aviatrix transit | ~50 GB | Included in GW | $0.00 |
| Internet egress (AppGW outbound) | ~20 GB | $0.087/GB | ~$1.74 |
| AppGW data processing | ~20 GB | $0.008/GB | ~$0.16 |
| **Subtotal Data Transfer** | | | **~$1.90** |

### Total Monthly Cost Summary

| Category | Monthly Cost |
|----------|-------------|
| Compute (VMs) | $410.85 |
| AKS Control Plane (Free tier) | $0.00 |
| Application Gateways | ~$370.84 |
| Networking (IPs, LBs, DNS) | ~$44.70 |
| Storage (OS disks) | ~$88.71 |
| Data Transfer | ~$1.90 |
| **TOTAL (estimated)** | **~$917/month** |

### Cost Breakdown

```
Compute (VMs)            █████████████░░░░░░░░░  52.2%  ($554)
Application Gateways     ████████░░░░░░░░░░░░░░  35.0%  ($371)
Storage                  ██░░░░░░░░░░░░░░░░░░░░   8.4%  ($89)
Networking               █░░░░░░░░░░░░░░░░░░░░░   4.2%  ($45)
Data Transfer            ░░░░░░░░░░░░░░░░░░░░░░   0.2%  (~$2)
```

> **Cost reduction options:**
> - **Azure Reserved Instances (1-year):** ~40% discount on VM and AppGW compute — saves ~$370/month
> - **AKS Free tier:** Suitable for labs; upgrade to Standard tier ($146/month) only if SLA is required
> - **Stop when not in use:** AKS clusters and gateways can be stopped; AppGW can be scaled to 0 instances
> - **AppGW is the dominant non-VM cost** due to the Standard_v2 fixed hourly rate ($0.246/hr regardless of traffic). No cheaper alternative exists for this architecture's asymmetric routing fix.

### Important Cost Exclusions

- **Aviatrix Licensing:** Separate licensing based on deployment type (PAYG via Azure Marketplace or BYOL). Contact Aviatrix for current rates.
- **Azure Monitor / Log Analytics:** If enabled for AKS diagnostics or AppGW access logs.
- **Azure Policy:** Enabled on AKS clusters; typically free for built-in policies.
- **Azure Support:** If not on the free Basic tier.

---

## Networking Details

### CIDR Allocation

| Network | CIDR | Purpose |
|---------|------|---------|
| Transit VNet | `10.2.0.0/20` | Aviatrix transit gateway |
| Frontend VNet | `10.10.0.0/23` | AKS frontend cluster |
| Backend VNet | `10.20.0.0/23` | AKS backend cluster |
| DB VNet | `10.5.0.0/22` | Test database spoke |
| Pod Overlay | `100.64.0.0/16` | Cilium pod IPs (same across all clusters, RFC 6598) |
| Service CIDR | `172.16.0.0/16` | Kubernetes service IPs |
| DNS Service IP | `172.16.0.10` | CoreDNS |

### Cilium Configuration

| Setting | Value | Purpose |
|---------|-------|---------|
| Network plugin | `azure` | Azure CNI managed by AKS |
| Network plugin mode | `overlay` | Cilium overlay for pod IPs |
| Pod CIDR | `100.64.0.0/16` | RFC 6598, same across all clusters |
| IP masquerade | Disabled (Azure-managed) | azure-ip-masq-agent excludes `100.64.0.0/16`; Aviatrix SNAT handles the translation. Not configurable via Cilium in this managed mode. |
| `outboundType` | `userDefinedRouting` | All egress via Aviatrix UDR |

---

## Tested With

| Component | Version |
|-----------|---------|
| Terraform | 1.14.0 |
| Aviatrix Controller | 9.0.10 |
| Aviatrix Provider | 8.2.0 |
| AzureRM Provider | 4.70.0 |
| TLS Provider | 4.2.1 |
| mc-transit module | 8.2.0 |
| mc-spoke module | 8.2.3 |
| Kubernetes | 1.33.8 |
| NGINX Ingress Chart | 4.12.0 |
| ExternalDNS Chart | 1.15.0 |
| k8s-firewall Chart | 8.2.0 |
| Gatus | v5.14.0 |

---

## Outputs

Each layer publishes outputs that the next layer (or operators) consume.

### `network/`

| Output | Type | Source / use |
|---|---|---|
| `frontend_appgw_public_ip`, `backend_appgw_public_ip` | string | Open Gatus dashboards |
| `frontend_spoke_gateway_private_ip`, `backend_spoke_gateway_private_ip` | string | Used by `azurerm_route` for the AKS UDR default route |
| `frontend_spoke_gateway_public_ip`, `backend_spoke_gateway_public_ip` | string | Auto-included in AKS `authorized_ip_ranges` |
| `transit_gateway_name`, `transit_vnet_id` | string | Reference / docs |
| `frontend_vnet_id`, `frontend_resource_group_name`, `frontend_nodes_subnet_id`, `frontend_system_subnet_id` (and `backend_*` equivalents) | string | Read by clusters/ layer |
| `frontend_route_table_id`, `backend_route_table_id` | string | Read by clusters/ for AKS identity role assignment |
| `frontend_cluster_name`, `backend_cluster_name` | string | Names AKS adopts |
| `private_dns_zone_id`, `private_dns_zone_name`, `dns_resource_group_name` | string | Workload Identity for ExternalDNS |
| `db_vm_private_ip`, `db_vm_name` | string | DB target IP for east-west tests |
| `pod_cidr`, `service_cidr`, `dns_service_ip` | string | Cluster network plumbing |
| `dcf_ruleset_uuid`, `smartgroup_*_uuid`, `webgroup_*_uuid` | string | DCF references for K8s CRD policies |

### `clusters/{frontend,backend}/`

| Output | Sensitive | Use |
|---|---|---|
| `cluster_name`, `cluster_id`, `cluster_fqdn` | no | Names / Azure resource ID |
| `host`, `client_certificate`, `client_key`, `cluster_ca_certificate`, `kube_config_raw` | yes | Consumed by nodes/ Helm + kubernetes providers |
| `oidc_issuer_url` | no | Workload Identity federation |
| `kubelet_identity_object_id`, `aks_identity_principal_id`, `external_dns_client_id` | no | Role assignment + Workload Identity binding |
| `resource_group_name`, `node_resource_group` | no | The `MC_*` group AKS auto-creates |
| `kubectl_config_command` | no | Copy/paste-friendly `az aks get-credentials …` |

### `nodes/{frontend,backend}/`

No outputs — this layer only installs Helm releases.

## Known Limitations

These are intentional behaviors a deployer should be aware of:

- **DCF egress allowlist is descriptive, not enforcing.** The DCF default action on this controller is PERMIT and the ruleset has no final DENY rule, so destinations not listed in any WebGroup (e.g., `example.com`, `iana.org`) still reach the internet. The blueprint's WebGroup-based PERMIT rules show the intended pattern; converting the allowlist to enforcement requires either changing the default action to DENY or adding a final low-priority DENY. If you do that, also add explicit allows for UDP/53 (DNS) and UDP/123 (NTP) so AKS itself keeps working.
- **Hostname-based SmartGroups for private FQDNs are not active.** `enable_vpc_dns_server = true` consistently fails the controller's DNS check on Controller 9.0.10 with the modules' default GW DNS configuration, so the blueprint disables it on every gateway. Hostname SmartGroups for the public Internet still work (controller resolves externally), but `frontend.azure.aviatrixdemo.local` / `backend.azure.aviatrixdemo.local` / `db.azure.aviatrixdemo.local` SmartGroups won't resolve targets — east-west enforcement falls through to the VNet-based SmartGroups, which is sufficient for the demonstrated traffic flows.
- **Threat-feed test IP rotates.** Aviatrix ThreatIQ ingests the [ET Open compromised-ips feed](https://rules.emergingthreats.net/blockrules/compromised-ips.txt), which rotates roughly daily. The IP referenced in `k8s-apps/{frontend,backend}/gatus.yaml` is a snapshot from one run and will eventually fall out of the feed. When that happens, pick a current IP from the feed and update both YAMLs:
  ```bash
  curl -s https://rules.emergingthreats.net/blockrules/compromised-ips.txt | grep -vE '^(#|$)' | head -1
  ```

## Additional Resources

- [Aviatrix Terraform Provider](https://registry.terraform.io/providers/AviatrixSystems/aviatrix/latest/docs)
- [Azure CNI Powered by Cilium](https://learn.microsoft.com/en-us/azure/aks/azure-cni-powered-by-cilium)
- [AKS outboundType userDefinedRouting](https://learn.microsoft.com/en-us/azure/aks/egress-outboundtype)
- [Azure Application Gateway for AKS](https://learn.microsoft.com/en-us/azure/application-gateway/ingress-controller-overview)
- [Aviatrix Distributed Cloud Firewall](https://docs.aviatrix.com/documentation/latest/security/dcf-reference-design-guide.html)
- [Workload Identity on AKS](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)

## Contributing

When making changes:

1. Always run `terraform fmt -recursive` before committing
2. Run `terraform validate` in all modified layers
3. Update this README if architectural decisions change
4. Test full deploy and destroy before submitting changes
5. Add new variables to `terraform.tfvars.example` with comments
