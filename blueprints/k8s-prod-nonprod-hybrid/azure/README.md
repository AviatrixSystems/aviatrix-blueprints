# k8s-prod-nonprod-hybrid — Azure (AKS)

This blueprint deploys a production and non-production AKS environment on Azure secured by the **Aviatrix Cloud Native Security Fabric (CNSF)**. It implements two-layer Distributed Cloud Firewall (DCF) isolation: environment-level enforcement via VNet SmartGroups, and namespace-level Zero Trust segmentation via Kubernetes SmartGroups — giving teams self-service egress control through FirewallPolicy CRDs while maintaining a hard boundary between prod and nonprod.

> [!TIP]
> **Optimized for Claude Code** — Run `/deploy-blueprint` for AI-guided deployment with prerequisite checks, or `/analyze-blueprint` for resource and cost details.

---

## Architecture

```
Transit GW (10.28.0.0/20, HA)
├── Prod Spoke    (10.10.0.0/20) ──── AKS prod-cluster
│                                         ├── namespace: team-a-prod
│                                         ├── namespace: team-b-prod
│                                         └── namespace: monitoring
├── NonProd Spoke (10.20.0.0/20) ──── AKS nonprod-cluster
│                                         ├── namespace: team-a-dev
│                                         ├── namespace: team-b-staging
│                                         ├── namespace: sandbox
│                                         └── namespace: monitoring
└── DB Spoke      (10.35.0.0/22)  ──── Database (prod-only)
```

See [`../architecture.svg`](../architecture.svg) for the full topology diagram.

**Two-layer DCF isolation:**

| Layer | Mechanism | Enforcement |
|---|---|---|
| Layer 1 | VNet SmartGroups | Prod VNet and NonProd VNet are bidirectionally denied. DB spoke is prod-only. |
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
| 50 | PERMIT | all-clusters egress HTTPS (AKS required Azure services) |
| 51 | PERMIT | sandbox egress HTTPS (relaxed, all hosts) |
| 70–99 | — | Reserved: team self-service via FirewallPolicy CRDs |

> **Azure note:** VNet SmartGroups match by VNet name (e.g. `patternc-xxxx-prod-vnet`). The `-vnet` suffix is added automatically by Aviatrix when VNets are onboarded.

---

## Prerequisites

### Aviatrix Infrastructure

| Component | Requirement | Notes |
|---|---|---|
| **Aviatrix Controller** | v8.x, provider ~> 8.2 | Must be deployed and reachable |
| **Aviatrix CoPilot** | Recommended | Required for DCF visualization and SmartGroups UI |
| **Azure Account Onboarded** | Account registered in Controller | Use exact account name as `azure_account_name` variable |

### Local Tools

| Tool | Version | Installation |
|---|---|---|
| **Terraform** | >= 1.5 | https://developer.hashicorp.com/terraform/install |
| **Azure CLI** | Latest | https://learn.microsoft.com/en-us/cli/azure/install-azure-cli |
| **kubectl** | Latest | https://kubernetes.io/docs/tasks/tools/ |
| **helm** | v3 | https://helm.sh/docs/intro/install/ |

### Azure Permissions

The Azure credentials must be able to create and manage:
- **AKS**: Clusters, node pools, managed identities, OIDC issuers
- **VNet**: Virtual networks, subnets, NSGs, route tables
- **Managed Identity**: User-assigned identities, role assignments (for Workload Identity)
- **Private DNS**: Private DNS zones and record sets

> **Tip:** `Contributor` + `User Access Administrator` roles work for demo environments.

### Environment Variables

```bash
# Aviatrix Controller credentials
export AVIATRIX_CONTROLLER_IP="your-controller.example.com"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="your-password"

# Azure credentials
export ARM_SUBSCRIPTION_ID="<subscription-id>"
export ARM_TENANT_ID="<tenant-id>"
export ARM_CLIENT_ID="<service-principal-app-id>"
export ARM_CLIENT_SECRET="<service-principal-secret>"

# Or use az login for interactive auth (development only)
az login
az account set --subscription "<subscription-id>"
```

---

## Resources Created

| Resource | Qty | Estimated $/hr |
|---|---|---|
| `aviatrix_transit_gateway` (Standard_D4_v2, HA) | 2 | ~$0.38 |
| `aviatrix_spoke_gateway` (Standard_D2_v2, HA each) | 6 | ~$0.96 |
| `aviatrix_vpc` (VNets) | 3 | — |
| `aviatrix_distributed_firewalling_config` | 1 (if `manage_dcf=true`) | — |
| `aviatrix_k8s_config` | 1 (if `manage_dcf=true`) | — |
| `aviatrix_smart_group` | 11 | — |
| `aviatrix_web_group` | 3 | — |
| `aviatrix_dcf_ruleset` | 1 | — |
| `azurerm_kubernetes_cluster` (prod + nonprod) | 2 | ~$0.10 each |
| `azurerm_kubernetes_cluster_node_pool` (Standard_D4_v3 × 2) | 2 | ~$0.19/node/hr |
| `azurerm_private_dns_zone` | 1 | ~$0.50/month |
| `helm_release` (ExternalDNS + k8s-firewall per cluster) | 4 | — |

**Estimated total: ~$2.00/hr** (HA enabled, East US 2 pricing)

> Disable HA (`enable_ha = false`) to approximately halve the Aviatrix gateway cost.

---

## Deployment Instructions

### Layer 1 — Network (~8 min)

```bash
cd azure/network

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set azure_account_name and azure_subscription_id

terraform init
terraform apply
```

### Layer 2 — Clusters (parallel, ~10 min)

```bash
cd azure/clusters/prod
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set azure_account_name and azure_subscription_id
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
cd azure/nodes/prod
cp terraform.tfvars.example terraform.tfvars
# Fill in: resource_group_name, cluster_name (from: terraform -chdir=../../clusters/prod output -raw cluster_name)
#           cluster_id (from: terraform -chdir=../../clusters/prod output -raw cluster_id)
#           dns_zone_name, dns_zone_resource_group (from: terraform -chdir=../../network output -raw private_dns_zone_name)
terraform init
terraform apply &

cd ../nonprod
cp terraform.tfvars.example terraform.tfvars
# Fill in same values using clusters/nonprod and network outputs
terraform init
terraform apply &
wait
```

### Layer 4 — K8s Apps

Get cluster credentials and apply CRDs:

```bash
# Get the cluster names from Layer 2
RESOURCE_GROUP=$(cd azure/network && terraform output -raw resource_group_name)

PROD_CLUSTER=$(cd azure/clusters/prod && terraform output -raw cluster_name)
NONPROD_CLUSTER=$(cd azure/clusters/nonprod && terraform output -raw cluster_name)

# Configure kubectl contexts
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$PROD_CLUSTER" --alias pc2-prod --overwrite-existing
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$NONPROD_CLUSTER" --alias pc2-nonprod --overwrite-existing

# Apply namespace manifests
kubectl --context pc2-prod apply -f azure/k8s-apps/dcf-crd/prod-namespaces.yaml
kubectl --context pc2-nonprod apply -f azure/k8s-apps/dcf-crd/nonprod-namespaces.yaml

# Apply FirewallPolicy CRDs
kubectl --context pc2-prod apply -f azure/k8s-apps/dcf-crd/firewallpolicy-prod.yaml
kubectl --context pc2-nonprod apply -f azure/k8s-apps/dcf-crd/firewallpolicy-nonprod.yaml
```

### Update Network Layer with Cluster IDs (Two-Pass Deployment)

After clusters register with the Controller, get the Aviatrix cluster IDs and re-apply the network layer:

```bash
# Get cluster IDs: CoPilot → Security → DCF → SmartGroups → create a K8s SmartGroup
# The Controller will list available cluster IDs.

cd azure/network
# Add to terraform.tfvars:
#   prod_cluster_id    = "<id-from-copilot>"
#   nonprod_cluster_id = "<id-from-copilot>"
terraform apply
```

---

## Variables Reference

### Network (`azure/network/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `azure_account_name` | `string` | — | yes | Aviatrix Azure account name (as registered in Controller) |
| `azure_subscription_id` | `string` | — | yes | Azure subscription ID |
| `azure_region` | `string` | `East US 2` | no | Azure region for all resources |
| `transit_cidr` | `string` | `10.28.0.0/20` | no | Transit VNet CIDR |
| `prod_vnet_cidr` | `string` | `10.10.0.0/20` | no | Production VNet CIDR |
| `nonprod_vnet_cidr` | `string` | `10.20.0.0/20` | no | Non-production VNet CIDR |
| `db_spoke_cidr` | `string` | `10.35.0.0/22` | no | Database spoke CIDR (prod-only) |
| `pod_cidr` | `string` | `100.64.0.0/16` | no | Overlay CIDR for pod networking (Azure CNI Overlay) |
| `name_prefix` | `string` | `pc2` | no | Prefix for all resource names |
| `enable_ha` | `bool` | `true` | no | Enable HA for all gateways |
| `prod_cluster_id` | `string` | `""` | no | Aviatrix cluster ID for prod AKS (set after clusters/ deploy) |
| `nonprod_cluster_id` | `string` | `""` | no | Aviatrix cluster ID for nonprod AKS (set after clusters/ deploy) |
| `random_suffix` | `bool` | `true` | no | Append random hex to resource names (prevents collisions) |
| `manage_dcf` | `bool` | `false` | no | Set `true` only if DCF is not already enabled on this Controller |

### Clusters (`azure/clusters/prod/` and `azure/clusters/nonprod/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `resource_group_name` | `string` | — | yes | Must match the Resource Group created in `azure/network/` |
| `vnet_id` | `string` | — | yes | ARM VNet resource ID — sourced from `network` output `prod_arm_vnet_id` / `nonprod_arm_vnet_id` |
| `subnet_id` | `string` | — | yes | AKS node pool subnet ID — sourced from `network` output `prod_aks_subnet_id` / `nonprod_aks_subnet_id` |
| `kubernetes_version` | `string` | `1.35` | no | Kubernetes version for AKS |
| `node_vm_size` | `string` | `Standard_D4s_v3` | no | VM size for the default node pool |
| `node_min_count` | `number` | `2` | no | Minimum node count (autoscaler) |
| `node_max_count` | `number` | `10` | no | Maximum node count (autoscaler) |
| `pod_cidr` | `string` | `100.64.0.0/16` | no | Pod CIDR for Azure CNI Overlay — must match `azure/network/` |

### Nodes (`azure/nodes/prod/` and `azure/nodes/nonprod/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `node_count` | `number` | `2` | no | Number of nodes per node pool |
| `node_vm_size` | `string` | `Standard_D4_v3` | no | VM size for worker nodes |
| `aviatrix_controller_ip` | `string` | — | yes | Aviatrix Controller IP |
| `aviatrix_username` | `string` | `admin` | no | Aviatrix Controller username |
| `aviatrix_password` | `string` | — | yes | Aviatrix Controller password (sensitive) |

---

## Test Scenarios

### Scenario 1 — Environment isolation (nonprod → prod blocked)

```bash
# Deploy a test service in prod
kubectl run --context=pc2-prod server --image=nginx --port=80 --expose

# Try to reach prod from nonprod (should be blocked — DCF DENY priority 11)
kubectl run --context=pc2-nonprod test --rm -it --image=curlimages/curl --restart=Never -- \
  curl --connect-timeout 5 http://10.10.0.100  # prod VNet IP
# Expected: connection timeout
```

### Scenario 2 — DB access (prod only)

```bash
# From prod, reach DB (should succeed — DCF PERMIT priority 20)
kubectl run --context=pc2-prod db-test --rm -it --image=mysql:8 --restart=Never -- \
  mysql -h 10.35.0.10 -u testuser -p --connect-timeout=5
# Expected: connection (or auth failure — not network timeout)

# From nonprod, reach DB (should be blocked — DCF DENY priority 21)
kubectl run --context=pc2-nonprod db-test --rm -it --image=mysql:8 --restart=Never -- \
  mysql -h 10.35.0.10 -u testuser -p --connect-timeout=5
# Expected: connection timeout
```

### Scenario 3 — Monitoring scrape

```bash
# From monitoring namespace, reach team pods on TCP/9090 (should succeed — priority 32)
kubectl run --context=pc2-prod monitor-test -n monitoring --rm -it \
  --image=curlimages/curl --restart=Never -- \
  curl http://team-a-service.team-a-prod:9090
# Expected: HTTP response
```

### Scenario 4 — Sandbox relaxed egress

```bash
# Sandbox can reach any HTTPS destination (priority 51 — relaxed egress)
kubectl run --context=pc2-nonprod sandbox-test -n sandbox --rm -it \
  --image=curlimages/curl --restart=Never -- \
  curl https://example.com
# Expected: HTTP response
```

---

## Cleanup / Destroy

**Destroy in reverse layer order.**

### Step 1 — Clean up Kubernetes resources

> **Before destroying nodes:** ExternalDNS creates Azure Private DNS records outside Terraform's view. Delete all Ingress and LoadBalancer Service resources **before** running `terraform destroy` on the nodes layer, otherwise those DNS records become orphaned and must be removed manually from the Private DNS zone.

```bash
for ctx in pc2-prod pc2-nonprod; do
  kubectl delete ingress --all -A --context=$ctx 2>/dev/null || true
  kubectl delete svc -A --field-selector spec.type=LoadBalancer --context=$ctx 2>/dev/null || true
done
```

### Step 2 — Destroy Layer 3: Nodes (parallel)

```bash
terraform -chdir=azure/nodes/prod destroy -auto-approve &
terraform -chdir=azure/nodes/nonprod destroy -auto-approve &
wait
```

### Step 3 — Destroy Layer 2: Clusters (parallel)

```bash
terraform -chdir=azure/clusters/prod destroy -auto-approve &
terraform -chdir=azure/clusters/nonprod destroy -auto-approve &
wait
```

### Step 4 — Destroy Layer 1: Network

```bash
terraform -chdir=azure/network destroy -auto-approve
```

---

## Troubleshooting

**VNet SmartGroup not matching expected traffic**

Azure VNet names have a `-vnet` suffix in the Aviatrix inventory. SmartGroups are defined using the full VNet name including suffix (e.g. `${name_prefix}-prod-vnet`). If SmartGroups do not match, verify the VNet name in Controller → Cloud Resources → VPCs/VNets.

**`aviatrix_kubernetes_cluster` fails: cluster not found**

The nodes layer reads the AKS cluster endpoint and CA certificate from the clusters layer state. Ensure the clusters layer has successfully completed before applying the nodes layer. If the cluster is newly created, wait 2–5 minutes for the Aviatrix Controller to sync its Kubernetes inventory.

**Namespace SmartGroups not enforcing**

K8s namespace SmartGroups require `prod_cluster_id` and `nonprod_cluster_id` in the network layer `terraform.tfvars`. Run the two-pass deployment: clusters first, then get the cluster IDs from CoPilot and re-apply the network layer. Without valid cluster IDs, the namespace SmartGroups match nothing.

**DCF rules not enforcing**

Verify DCF is `Enabled` in CoPilot → Security → DCF. If `manage_dcf = false`, DCF must have been enabled externally. Also verify that `aviatrix_k8s_config` is applied (either directly by this blueprint or by another blueprint on the same controller).

---

## Outputs Reference

### Network (`azure/network/`)

| Output | Description |
|--------|-------------|
| `transit_gw_name` | Aviatrix Transit Gateway name |
| `prod_vnet_id` | Production VNet ID (Aviatrix format) |
| `prod_vnet_name` | Production VNet name |
| `prod_arm_vnet_id` | Production VNet ARM resource ID |
| `nonprod_vnet_id` | Non-production VNet ID (Aviatrix format) |
| `nonprod_vnet_name` | Non-production VNet name |
| `nonprod_arm_vnet_id` | Non-production VNet ARM resource ID |
| `db_vnet_id` | Database spoke VNet ID (Aviatrix format) |
| `prod_spoke_gw_name` | Production spoke gateway name |
| `nonprod_spoke_gw_name` | Non-production spoke gateway name |
| `db_spoke_gw_name` | Database spoke gateway name |
| `private_dns_zone_name` | Azure Private DNS zone name |
| `private_dns_zone_id` | Azure Private DNS zone resource ID |
| `sg_prod_vpc_uuid` | UUID of the production VPC SmartGroup |
| `sg_nonprod_vpc_uuid` | UUID of the non-production VPC SmartGroup |
| `sg_prod_db_uuid` | UUID of the production database SmartGroup |
| `name_prefix` | Name prefix with random suffix |
| `prod_aks_subnet_id` | Production AKS node pool subnet ID |
| `nonprod_aks_subnet_id` | Non-production AKS node pool subnet ID |
| `azure_subscription_id` | Azure subscription ID |
| `azure_region` | Azure region |
| `resource_group_name` | Azure Resource Group name |
| `private_dns_zone_resource_group` | Resource group containing the Private DNS zone |

### Clusters (`azure/clusters/prod/` and `azure/clusters/nonprod/`)

| Output | Description |
|--------|-------------|
| `cluster_name` | AKS cluster name |
| `cluster_id` | AKS cluster resource ID |
| `cluster_fqdn` | AKS cluster FQDN |
| `kube_config` | AKS cluster kubeconfig *(sensitive)* |
| `oidc_issuer_url` | OIDC issuer URL for Workload Identity |
| `kubelet_identity_object_id` | Kubelet managed identity object ID |
| `node_resource_group` | Auto-generated node resource group name |

Nodes layers expose no outputs.

---

## Tested With

| Component | Version |
|---|---|
| Aviatrix Controller | 8.x |
| Aviatrix Terraform Provider | 8.2.10 |
| Terraform | 1.12.2 |
| Azure Provider (`azurerm`) | 4.75.0 |
| Kubernetes Provider | 2.38.0 |
| Helm Provider | 2.17.0 |
| Kubernetes | 1.35 (AKS) |
