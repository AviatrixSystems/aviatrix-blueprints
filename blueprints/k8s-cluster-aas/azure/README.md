# Kubernetes Cluster-as-a-Service — Azure (AKS)

Each team gets a **dedicated AKS cluster in its own VNet**. Workload isolation is enforced by the **Aviatrix Cloud Native Security Fabric (CNSF)** — Distributed Cloud Firewall (DCF) at the VNet boundary — so no team can reach another team's cluster without an explicit PERMIT rule. This blueprint demonstrates VNet-level SmartGroup segmentation, post-SNAT DCF enforcement, GeoBlock/ThreatIQ threat prevention, and egress control via WebGroups.

---

## Architecture Diagram

![Architecture Diagram](../architecture.svg)

**Data flow:** Pods use Azure CNI Overlay with an RFC 6598 overlay CIDR (`100.64.0.0/16`). Each spoke gateway applies custom SNAT, translating pod IPs to the spoke gateway's private IP before traffic enters the Aviatrix transit. DCF evaluates **post-SNAT traffic** — use VPC-type SmartGroups (matching VNet name) to identify source teams, and hostname-type SmartGroups to identify service destinations.

```
Internet
    │ (blocked by default unless WebGroup permits)
    ▼
Transit GW (10.28.0.0/20)  ◄── DCF evaluates here (post-SNAT)
├── Team-A Spoke (10.30.0.0/20) ── AKS cluster-a  [pods: 100.64.0.0/18]
├── Team-B Spoke (10.31.0.0/20) ── AKS cluster-b  [pods: 100.64.64.0/18]
├── Team-C Spoke (10.32.0.0/20) ── AKS cluster-c  [pods: 100.64.128.0/18]
└── DB Spoke    (10.35.0.0/22)  ── Shared database
```

### DCF Policy Layout

| Priority | Action | Rule |
|---|---|---|
| 0 | DENY | Geo-block (IR, KP, RU) |
| 1 | DENY | ThreatIQ (major + critical) |
| 10 | PERMIT | team-a → team-b TCP/443 |
| 11 | PERMIT | team-b → team-a TCP/8080 |
| 20 | DENY | team-a → team-c (bidirectional at 20–23) |
| 50 | PERMIT | all clusters → AKS required Azure services (TCP/443) |

> **Note:** VNet SmartGroups match on VNet name (e.g. `team-a-vnet`). DCF sees post-SNAT spoke-gateway IPs, not pod IPs.

---

## Prerequisites

### Aviatrix Infrastructure

| Component | Requirement | Notes |
|---|---|---|
| **Aviatrix Controller** | Version compatible with provider ~> 8.2 | Must be deployed and reachable |
| **Aviatrix CoPilot** | Recommended | Required for DCF visualization and SmartGroups UI |
| **Azure Account Onboarded** | Account registered in Controller | Use the exact account name in `terraform.tfvars` |

### Local Tools

| Tool | Version | Installation | Purpose |
|---|---|---|---|
| **Terraform** | >= 1.5 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure provisioning |
| **Azure CLI** | Latest | [Install Guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) | Azure authentication and AKS kubeconfig |
| **kubectl** | Latest | [Install Guide](https://kubernetes.io/docs/tasks/tools/) | Kubernetes cluster interaction |

### Azure Permissions

The Azure credentials must have permissions to create and manage:
- **AKS**: Kubernetes clusters, node pools, managed identities, OIDC issuers
- **VNet**: Virtual networks, subnets, network security groups, route tables
- **Managed Identity**: User-assigned identities, role assignments (for Workload Identity)
- **Private DNS**: Private DNS zones and record sets
- **Load Balancer**: Application gateways, standard load balancers

> **Tip:** `Contributor` + `User Access Administrator` roles work for demo environments. For production, create a custom role scoped to the resource group.

### Environment Variables

```bash
# Aviatrix Controller credentials
export AVIATRIX_CONTROLLER_IP="<controller-ip-or-hostname>"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="<password>"

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

| Resource | Count | Est. Hourly Cost |
|---|---|---|
| `aviatrix_transit_gateway` (Standard_D4_v2) | 1 | ~$0.19 |
| `aviatrix_spoke_gateway` (Standard_B2ms, no HA) | 3 | ~$0.05 each |
| `aviatrix_vpc` (transit + 3 team + DB) | 5 | — |
| `aviatrix_spoke_transit_attachment` | 4 | — |
| `aviatrix_gateway_snat` | 3 | — |
| `aviatrix_distributed_firewalling_config` | 0 or 1 | — |
| `aviatrix_k8s_config` | 0 or 1 | — |
| `aviatrix_kubernetes_cluster` | 3 | — |
| `aviatrix_smart_group` | 9 | — |
| `aviatrix_web_group` | 3 | — |
| `aviatrix_dcf_ruleset` | 1 | — |
| `azurerm_kubernetes_cluster` | 3 | ~$0.10 each (control plane) |
| `azurerm_kubernetes_cluster_node_pool` (Standard_D4_v3 × 2) | 3 | ~$0.19/node/hr |
| `azurerm_private_dns_zone` | 1 | ~$0.50/month |
| `helm_release` (ExternalDNS + k8s-firewall per cluster) | 6 | — |

**Estimated total:** ~$1.30/hour (3 clusters, 2 nodes each, East US 2 pricing).

> Aviatrix licensing costs are separate and depend on your subscription type.

---

## Deployment Instructions

### Step 1 — Set environment variables

```bash
export AVIATRIX_CONTROLLER_IP="<controller-ip>"
export AVIATRIX_USERNAME="admin"
export AVIATRIX_PASSWORD="<password>"
export ARM_SUBSCRIPTION_ID="<subscription-id>"

# Verify Azure credentials
az account show
```

### Step 2 — Deploy Layer 1: Network (~8 min)

```bash
cd azure/network
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set aviatrix_azure_account_name and azure_subscription_id
vim terraform.tfvars

terraform init
terraform apply
```

**What is created:** Aviatrix transit gateway, 4 VNets (transit + 3 team + DB), 3 spoke gateways, spoke-to-transit attachments, custom SNAT rules (pod CIDR → spoke GW IP), Azure Private DNS zone, and the DCF ruleset.

### Step 3 — Deploy Layer 2: AKS Clusters (parallel, ~10 min)

```bash
for team in team-a team-b team-c; do
  cd azure/clusters/$team
  cp terraform.tfvars.example terraform.tfvars
  # Edit terraform.tfvars: set aviatrix_azure_account_name and azure_subscription_id
  terraform init
  terraform apply -auto-approve &
  cd ../../..
done
wait
```

**What is created:** AKS cluster per team, system node pool, OIDC issuer, Workload Identity federation for ExternalDNS and the k8s-firewall agent.

### Step 4 — Deploy Layer 3: Node Groups (parallel, ~5 min)

```bash
for team in team-a team-b team-c; do
  cd azure/nodes/$team
  terraform init
  terraform apply -auto-approve &
  cd ../../..
done
wait
```

**What is created:** User node pools, ExternalDNS helm chart, k8s-firewall helm chart (for DCF Layer 2 enforcement).

### Step 5 — Configure kubectl

```bash
RESOURCE_GROUP=$(cd azure/network && terraform output -raw resource_group_name)

for team in team-a team-b team-c; do
  cluster_name=$(cd azure/clusters/$team && terraform output -raw cluster_name)
  az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$cluster_name" \
    --alias $team \
    --overwrite-existing
done

# Verify all three clusters are accessible
kubectl config get-contexts
kubectl get nodes --context=team-a
kubectl get nodes --context=team-b
kubectl get nodes --context=team-c
```

---

## Variables Reference

### Network (`azure/network/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `aviatrix_azure_account_name` | string | — | yes | Azure account name as registered in Aviatrix Controller |
| `azure_subscription_id` | string | — | yes | Azure subscription ID for the azurerm provider |
| `azure_region` | string | `East US 2` | no | Azure region for all resources |
| `name_prefix` | string | `caas` | no | Prefix for all resource names |
| `transit_cidr` | string | `10.28.0.0/20` | no | CIDR for the Aviatrix transit VNet |
| `team_a_vnet_cidr` | string | `10.30.0.0/20` | no | Primary CIDR for team-a AKS VNet |
| `team_b_vnet_cidr` | string | `10.31.0.0/20` | no | Primary CIDR for team-b AKS VNet |
| `team_c_vnet_cidr` | string | `10.32.0.0/20` | no | Primary CIDR for team-c AKS VNet |
| `db_vnet_cidr` | string | `10.35.0.0/22` | no | CIDR for the database spoke VNet |
| `pod_cidr` | string | `100.64.0.0/16` | no | Overlay CIDR for pod networking (RFC 6598) |
| `private_dns_zone_name` | string | `azure.aviatrixdemo.local` | no | Azure Private DNS zone name |
| `db_private_ip` | string | `10.35.0.10` | no | Private IP address of the database (DNS A record) |
| `random_suffix` | bool | `true` | no | Append random hex suffix to all resource names |
| `manage_dcf` | bool | `false` | no | Whether this blueprint manages DCF global enable/disable |

### Cluster (`azure/clusters/team-*/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `aviatrix_azure_account_name` | string | — | yes | Aviatrix access account name for Azure |
| `azure_subscription_id` | string | — | yes | Azure subscription ID |
| `kubernetes_version` | string | `1.31` | no | Kubernetes version for the AKS cluster |
| `sku_tier` | string | `Standard` | no | AKS pricing tier (`Free`, `Standard`, `Premium`) |

### Nodes (`azure/nodes/team-*/`)

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `node_count` | number | `2` | no | Number of nodes in the user node pool |
| `node_vm_size` | string | `Standard_D4_v3` | no | VM size for worker nodes |
| `aviatrix_controller_ip` | string | — | yes | Aviatrix Controller IP (for k8s-firewall helm values) |
| `aviatrix_username` | string | `admin` | no | Aviatrix Controller username |
| `aviatrix_password` | string | — | yes | Aviatrix Controller password (sensitive) |

---

## Outputs Reference

### Network (`azure/network/`)

| Output | Description |
|---|---|
| `transit_gateway_name` | Aviatrix transit gateway name (sensitive) |
| `resource_group_name` | Azure resource group containing all resources |
| `team_a_vnet_id` | Team-A VNet ID |
| `team_a_spoke_gateway_name` | Team-A spoke gateway name (sensitive) |
| `team_a_cluster_name` | Team-A AKS cluster name |
| `team_b_vnet_id` | Team-B VNet ID |
| `team_b_spoke_gateway_name` | Team-B spoke gateway name (sensitive) |
| `team_b_cluster_name` | Team-B AKS cluster name |
| `team_c_vnet_id` | Team-C VNet ID |
| `team_c_spoke_gateway_name` | Team-C spoke gateway name (sensitive) |
| `team_c_cluster_name` | Team-C AKS cluster name |
| `private_dns_zone_name` | Azure Private DNS zone domain name |
| `dcf_ruleset_uuid` | UUID of the DCF ruleset |

### Cluster (`azure/clusters/team-*/`)

| Output | Description |
|---|---|
| `cluster_name` | AKS cluster name |
| `cluster_id` | AKS cluster resource ID |
| `cluster_endpoint` | AKS API server endpoint |
| `cluster_ca_certificate` | Base64 encoded CA certificate (sensitive) |
| `oidc_issuer_url` | OIDC issuer URL for Workload Identity |
| `kubelet_identity_object_id` | Kubelet managed identity object ID |

### Nodes (`azure/nodes/team-*/`)

Nodes workspaces expose no outputs — node pools are consumed by Kubernetes directly.

---

## Test Scenarios

### Scenario 1 — Permitted east-west traffic (team-a → team-b on TCP/443)

```bash
# Deploy a test server in team-b
kubectl run --context=team-b server --image=nginx --port=443 --expose

# Test connectivity from team-a (should succeed — DCF PERMIT rule 10)
kubectl run --context=team-a test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -k https://team-b.azure.aviatrixdemo.local
# Expected: HTTP response
```

### Scenario 2 — Blocked east-west traffic (team-a → team-c, any port)

```bash
# Test connectivity from team-a to team-c (should be blocked — DCF DENY rule 20)
kubectl run --context=team-a test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -k --connect-timeout 5 https://team-c.azure.aviatrixdemo.local
# Expected: connection timeout
```

### Scenario 3 — Permitted egress to AKS required services (MCR, ARM)

```bash
# Test egress to Microsoft Container Registry (should succeed — WebGroup PERMIT)
kubectl run --context=team-a test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -k --connect-timeout 5 https://mcr.microsoft.com
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
# Wait ~60 seconds for ExternalDNS to clean up DNS records
```

### Step 2 — Destroy Layer 3: Nodes (parallel)

```bash
for team in team-a team-b team-c; do
  terraform -chdir=azure/nodes/$team destroy -auto-approve &
done
wait
```

### Step 3 — Destroy Layer 2: Clusters (parallel)

```bash
for team in team-a team-b team-c; do
  terraform -chdir=azure/clusters/$team destroy -auto-approve &
done
wait
```

### Step 4 — Destroy Layer 1: Network

```bash
terraform -chdir=azure/network destroy -auto-approve
```

---

## Troubleshooting

**`aviatrix_kubernetes_cluster` fails: cluster not found**

The nodes layer must be applied after the AKS cluster is in `Succeeded` provisioning state and the Aviatrix Controller has completed its Kubernetes inventory sync (typically 2–5 min after node pools join). Re-run `terraform apply` in the nodes layer for the affected team if this fails.

**Pods cannot reach external services**

Verify SNAT rules are applied: Aviatrix Controller → Gateways → [spoke gateway] → SNAT. The pod CIDR `100.64.0.0/16` must map to the spoke gateway's private IP. If SNAT rules are missing, re-apply the network layer.

**DCF rules not enforcing**

Check that DCF is in `Enabled` state in CoPilot → Security → Distributed Cloud Firewall. Confirm VNet-type SmartGroups are selecting the correct VNets by name (names include `-vnet` suffix in Azure).

**AKS nodes not joining due to NSG rules**

Aviatrix spoke gateway NSGs may conflict with AKS-required outbound rules. Ensure the AKS outbound type is set to `loadBalancer` (default) and that the Aviatrix-managed NSG does not block AKS management traffic on port 443 to `*.hcp.*.azmk8s.io`.

**Workload Identity not resolving**

If ExternalDNS or k8s-firewall pods fail with token errors, verify the OIDC issuer is enabled on the AKS cluster (`oidc_issuer_enabled = true`) and the federated credential subject matches the Kubernetes service account namespace/name exactly.

---

## Tested With

| Component | Version |
|---|---|
| Aviatrix Controller | 7.2+ |
| Aviatrix Terraform Provider | ~> 8.2.0 |
| Terraform | >= 1.5 |
| Azure Provider (`azurerm`) | ~> 4.0 |
| Kubernetes Provider | ~> 2.20 |
| Helm Provider | ~> 2.x |
| Kubernetes | 1.31 (AKS) |
