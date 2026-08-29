# Namespace-as-a-Service — Azure (AKS)

All teams share a **single AKS cluster** with namespace-level workload isolation enforced by the **Aviatrix Cloud Native Security Fabric (CNSF)** — Distributed Cloud Firewall (DCF) at the transit layer. Kubernetes RBAC prevents accidental cross-namespace access but is not a security boundary; DCF is the enforcement mechanism.

---

## Architecture Diagram

<!-- TODO: Add architecture diagram — place architecture.png or architecture.svg in this directory -->

```
Transit VNet (10.28.0.0/20)
  Aviatrix Transit GW
      │
      └── Shared Spoke VNet (10.30.0.0/16)
              Aviatrix Spoke GW (SNAT: 100.64.0.0/16 → spoke-ip)
                  │
                  └── AKS Shared Cluster (Azure CNI Overlay)
                          ├── namespace: team-a  [pods: 100.64.x.x]
                          ├── namespace: team-b  [pods: 100.64.x.x]
                          └── namespace: team-c  [pods: 100.64.x.x]
```

Pod traffic uses Azure CNI Overlay with the RFC 6598 CIDR (`100.64.0.0/16`). The Aviatrix spoke gateway SNATs pod IPs to the spoke gateway IP for east-west and egress traffic. DCF SmartGroups match on the originating Kubernetes namespace.

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
| 60 | PERMIT | All namespaces → public internet (AKS required + approved domains, TCP/443) |
| 70–99 | (reserved) | CRD-managed team self-service rules (GitOps) |

---

## Prerequisites

### Aviatrix Controller

| Requirement | Details |
|---|---|
| Aviatrix Controller | Version compatible with provider ~> 8.2; must be running and accessible |
| Aviatrix CoPilot | Recommended for DCF visualization and SmartGroups UI |
| Azure Account Onboarded | Account name registered in the Controller (used for `aviatrix_azure_account_name`) |
| DCF Enabled | Either pre-enabled by your Controller admin OR set `manage_dcf = true` if this blueprint owns DCF lifecycle |

### Local Tools

| Tool | Min Version | Notes |
|---|---|---|
| Terraform | >= 1.5 | [Install](https://developer.hashicorp.com/terraform/install) |
| Azure CLI | Latest | [Install](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) — used for AKS credentials |
| kubectl | Latest | [Install](https://kubernetes.io/docs/tasks/tools/) |
| helm | Latest | [Install](https://helm.sh/docs/intro/install/) |

### Azure IAM Permissions

The service principal or managed identity must have permissions to create:
- AKS: clusters, node pools, managed identities, federated credentials
- Virtual Networks: VNets, subnets, NSGs, route tables
- Private DNS: zones, virtual network links, record sets
- Resource Groups: create and manage
- Role Assignments: assign managed identity roles (Contributor, DNS Zone Contributor)

> The `Contributor` role at the subscription level covers all required permissions for demo environments.

### Environment Variables

```bash
# Aviatrix Controller
export AVIATRIX_CONTROLLER_IP="your-controller-ip"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="your-password"

# Azure credentials (choose one method)
# Option 1: az login (interactive)
az login
az account set --subscription "your-subscription-id"

# Option 2: service principal
export ARM_CLIENT_ID="your-client-id"
export ARM_CLIENT_SECRET="your-client-secret"
export ARM_SUBSCRIPTION_ID="your-subscription-id"
export ARM_TENANT_ID="your-tenant-id"
```

---

## Resources Created

| Resource | Qty | Estimated hourly cost |
|---|---|---|
| `aviatrix_transit_gateway` | 1 | ~$0.17/hr |
| `aviatrix_vpc` (transit VNet) | 1 | — |
| `aviatrix_spoke_gateway` (shared, no HA) | 1 | ~$0.04/hr |
| `aviatrix_spoke_transit_attachment` | 1 | — |
| `aviatrix_distributed_firewalling_config` | 0 or 1 | — (only if manage_dcf=true) |
| `aviatrix_k8s_config` | 0 or 1 | — (only if manage_dcf=true) |
| `aviatrix_kubernetes_cluster` | 1 | — |
| `aviatrix_smart_group` | 8 | — |
| `aviatrix_web_group` | 2 | — |
| `aviatrix_dcf_ruleset` | 1 | — |
| `azurerm_kubernetes_cluster` | 1 | ~$0.10/hr (control plane) |
| `azurerm_kubernetes_cluster_node_pool` (system) | 1 | — (built-in) |
| Node VMs (3× Standard_D4s_v3 Spot) | 3 | ~$0.05–0.09/hr each |
| `azurerm_private_dns_zone` | 1 | ~$0.50/mo |
| `azurerm_user_assigned_identity` (ExternalDNS, ingress) | 2 | — |
| `helm_release` (nginx-ingress, ExternalDNS) | 2 | — |

> Estimated cost at defaults (East US 2, 3 Spot nodes, no HA): roughly **$0.50–0.65/hr** (~$360–470/month). Aviatrix licensing is billed separately.

---

## Deployment Instructions

### Step 0 — Set environment variables

```bash
export AVIATRIX_CONTROLLER_IP="your-controller-ip"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="your-password"

# Verify Azure credentials
az account show
```

### Step 1 — Layer 1: Network (~10 min)

```bash
cd azure/network

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   aviatrix_azure_account_name = "your-aviatrix-account-name"
#   azure_subscription_id       = "your-subscription-id"
#   azure_region                = "East US 2"
#   # Leave k8s_cluster_id empty for now — fill in after Step 2

terraform init
terraform apply -var-file=terraform.tfvars
```

### Step 2 — Layer 2: Shared AKS Cluster (~15 min)

```bash
cd azure/clusters/shared

cp terraform.tfvars.example terraform.tfvars
# Edit if needed (all variables have defaults)

terraform init
terraform apply -var-file=terraform.tfvars

# Note the cluster_id output — needed for DCF SmartGroups
terraform output cluster_id
```

### Step 2b — Update network layer with cluster ID (SmartGroups)

```bash
cd azure/network

# Edit terraform.tfvars:
#   k8s_cluster_id = "<cluster_id from Step 2>"
#   # Format: /subscriptions/{sub}/resourcegroups/{rg}/providers/Microsoft.ContainerService/managedClusters/{name}

terraform apply -var-file=terraform.tfvars
```

### Step 3 — Layer 3: Node Pool + Helm Add-ons (~8 min)

```bash
cd azure/nodes/shared

terraform init
terraform apply
# No tfvars required if using defaults; create one from the example if customizing
```

### Step 4 — Layer 4: Kubernetes Apps (< 1 min)

```bash
# Configure kubectl
cd azure/clusters/shared
$(terraform output -raw kubectl_config_command)

# Apply namespace isolation CRDs and network policies
kubectl apply -f azure/k8s-apps/dcf-crd/
```

---

## Variables Reference

### Layer 1 — azure/network

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `name_prefix` | string | `"naas"` | No | Prefix for all resource names |
| `aviatrix_azure_account_name` | string | — | **Yes** | Azure account name registered in the Aviatrix Controller |
| `azure_subscription_id` | string | — | **Yes** | Azure subscription ID for the azurerm provider |
| `azure_region` | string | `"East US 2"` | No | Azure region |
| `env` | string | `"prod"` | No | Environment tag value |
| `transit_cidr` | string | `"10.28.0.0/20"` | No | CIDR for the Aviatrix transit VNet |
| `shared_vnet_cidr` | string | `"10.30.0.0/16"` | No | CIDR for the shared cluster VNet |
| `pod_cidr` | string | `"100.64.0.0/16"` | No | Overlay CIDR for pod networking (Azure CNI Overlay, RFC 6598) |
| `private_dns_zone_name` | string | `"azure-naas.aviatrixdemo.local"` | No | Azure Private DNS zone name |
| `k8s_cluster_suffix` | string | `"shared-aks"` | No | Suffix appended to `name_prefix` for the cluster name |
| `k8s_cluster_id` | string | `""` | No | AKS cluster resource ID for DCF SmartGroups (fill in after clusters/shared/ apply) |
| `team_namespaces` | list(string) | `["team-a","team-b","team-c"]` | No | Team namespace names (SmartGroup naming only — DCF rules are hardcoded) |
| `geo_block_countries` | list(string) | `["CN","RU","KP","IR"]` | No | ISO country codes to geo-block |
| `approved_web_domains` | list(string) | `["*.blob.core.windows.net","ghcr.io",…]` | No | Domains permitted for namespace egress |
| `random_suffix` | bool | `true` | No | Append random hex to resource names |
| `manage_dcf` | bool | `false` | No | Set `true` only if this blueprint owns DCF lifecycle on the controller |

### Layer 2 — azure/clusters/shared

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `kubernetes_version` | string | `"1.35"` | No | AKS Kubernetes version |

### Layer 3 — azure/nodes/shared

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `node_pool_config` | object | `{min=2, max=6, count=3, Standard_D4s_v3, Spot}` | No | AKS user node pool configuration |
| `nginx_ingress_chart_version` | string | `"4.11.0"` | No | Helm chart version for nginx-ingress |
| `external_dns_chart_version` | string | `"1.15.0"` | No | Helm chart version for ExternalDNS |

---

## Outputs Reference

### azure/network outputs

| Output | Description |
|---|---|
| `transit_gateway_name` | Aviatrix transit gateway name |
| `transit_vnet_id` | Transit VNet ID |
| `shared_vnet_id` | Shared cluster VNet ID (Aviatrix format) |
| `shared_vnet_name` | Shared cluster VNet name |
| `shared_vnet_cidr` | Shared cluster VNet primary CIDR |
| `shared_resource_group_name` | Resource group containing the shared VNet |
| `shared_arm_vnet_id` | Shared VNet ARM resource ID |
| `shared_aks_system_subnet_id` | AKS system node pool subnet ID |
| `shared_aks_system_subnet_cidr` | AKS system node pool subnet CIDR |
| `shared_spoke_gateway_name` | Shared spoke gateway name |
| `shared_spoke_gateway_private_ip` | Spoke gateway private IP (SNAT target) |
| `private_dns_zone_id` | Azure Private DNS zone ID |
| `private_dns_zone_name` | Azure Private DNS zone name |
| `private_dns_zone_resource_group` | Resource group containing the Private DNS zone |
| `shared_cluster_name` | AKS cluster name |
| `azure_region` | Azure region |
| `pod_cidr` | Pod overlay CIDR |
| `name_prefix` | Name prefix used for all resources |

### azure/clusters/shared outputs

| Output | Description |
|---|---|
| `cluster_id` | AKS cluster resource ID (input for `k8s_cluster_id` in network layer) |
| `cluster_name` | AKS cluster name |
| `cluster_version` | Kubernetes version |
| `cluster_endpoint` | AKS API server endpoint |
| `cluster_certificate_authority_data` | Base64 cluster CA cert |
| `node_resource_group` | Auto-generated resource group for AKS node infrastructure |
| `oidc_issuer_url` | OIDC issuer URL for Workload Identity |
| `external_dns_identity_client_id` | Client ID of ExternalDNS managed identity |
| `ingress_identity_client_id` | Client ID of ingress controller managed identity |
| `kubectl_config_command` | `az aks get-credentials` command |

azure/nodes/shared exposes no outputs.

---

## Test Scenarios

### Scenario 1: Baseline namespace isolation

```bash
# Configure kubectl
cd azure/clusters/shared
$(terraform output -raw kubectl_config_command)

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

# Test: monitoring -> team-a on TCP/80 (no PERMIT rule — expect DENY)
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
# Step 1: Remove Kubernetes resources (LoadBalancers, DNS records)
kubectl delete -f azure/k8s-apps/dcf-crd/
kubectl delete svc -A --field-selector spec.type=LoadBalancer
kubectl delete ingress --all -A
# Wait ~60 seconds for Azure to de-register LBs

# Step 2: Destroy Layer 3 — nodes
terraform -chdir=azure/nodes/shared destroy -auto-approve

# Step 3: Destroy Layer 2 — cluster
terraform -chdir=azure/clusters/shared destroy -auto-approve

# Step 4: Destroy Layer 1 — network
terraform -chdir=azure/network destroy -var-file=terraform.tfvars -auto-approve
```

**Manual cleanup steps:**

- If ExternalDNS-managed Private DNS records are not removed before Step 2, they will be orphaned. List them with:
  ```bash
  az network private-dns record-set list \
    --resource-group <rg-name> \
    --zone-name azure-naas.aviatrixdemo.local
  ```
- If `manage_dcf = true`, verify DCF and `k8s_config` are in the desired state after destroy. These are shared controller resources.

**Verify cleanup:**

```bash
terraform -chdir=azure/network state list
terraform -chdir=azure/clusters/shared state list
terraform -chdir=azure/nodes/shared state list

# Confirm no AKS clusters remain
az aks list --subscription your-subscription-id --output table
```

---

## Troubleshooting

**Namespace SmartGroups not enforcing**

DCF namespace enforcement requires the Aviatrix Controller to have read access to the AKS cluster. The clusters/shared/ layer creates managed identities and configures Workload Identity for this purpose. In CoPilot, go to Security → Distributed Cloud Firewall → SmartGroups and confirm team namespaces appear as populated groups.

**`k8s_cluster_id` mismatch — pods not matching SmartGroups**

The `k8s_cluster_id` must be the full AKS resource ID (format: `/subscriptions/.../managedClusters/...`). After applying clusters/shared/, run `terraform output cluster_id` in that directory and set the value in the network layer's `terraform.tfvars`. Re-apply the network layer.

**AKS node pool quota exceeded**

Azure imposes per-region vCPU quotas. Standard_D4s_v3 uses 4 vCPUs each; 3 nodes requires 12 vCPUs. Check your quota at: Portal → Subscriptions → Usage + quotas → filter by region and VM family.

**Pods not getting 100.64.x.x addresses**

AKS with Azure CNI Overlay assigns pod IPs from the overlay CIDR automatically. If pods show node-CIDR addresses instead, verify the cluster was created with `network_plugin = "azure"` and `network_plugin_mode = "overlay"`. Check with:
```bash
kubectl get pods -A -o wide | grep -v 10\.30
```

**ExternalDNS fails with permission errors**

ExternalDNS uses Workload Identity to update Azure Private DNS. Verify the federated credential and role assignment were created by clusters/shared/. Check ExternalDNS logs:
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns --tail=20
```

**`terraform destroy` hangs on `aviatrix_kubernetes_cluster`**

The Controller deregisters the cluster asynchronously. If destroy hangs beyond 5 minutes, check CoPilot → Infrastructure → Kubernetes to confirm the cluster was removed, then run `terraform state rm aviatrix_kubernetes_cluster.this` and retry.

**Aviatrix spoke gateway creation fails with "subnet not found"**

The `aviatrix_vpc` resource for the shared VNet creates subnets that the spoke gateway references. If the VNet and gateway creation are in the same apply, timing can cause this error. Run `terraform apply` a second time if this occurs.

---

## Tested With

| Component | Version |
|---|---|
| Aviatrix Controller | 7.2.x |
| Aviatrix Terraform Provider | ~> 8.2.0 |
| Terraform | >= 1.5 |
| Azure Provider (azurerm) | ~> 4.0 |
| Kubernetes Provider | ~> 2.20 |
| Helm Provider | ~> 2.x |
| AKS Kubernetes version | 1.35 |
| nginx-ingress chart | 4.11.0 |
| ExternalDNS chart | 1.15.0 |
