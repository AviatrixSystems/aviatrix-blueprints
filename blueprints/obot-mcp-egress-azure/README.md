# Zero-Trust MCP Egress: Obot on AKS with Aviatrix DCF

Deploy [Obot](https://obot.ai) onto a new AKS cluster with network-layer zero-trust egress enforcement for all MCP server pods. An Aviatrix spoke gateway intercepts outbound traffic; MCPNetworkPolicy CRDs (reconciled by Obot's bundled aviatrix-network-policy-controller) translate per-server allowlists into live FirewallPolicy rules. No sidecars, no service mesh, no code changes required.

## Architecture

![Architecture Diagram](architecture.svg)

Traffic flow:

1. Obot user creates an MCP server and configures its allowed egress domains via the Obot UI or API.
2. Obot's bundled `aviatrix-network-policy-controller` reconciles the server's `MCPNetworkPolicy` into an Aviatrix `FirewallPolicy` CRD.
3. The Aviatrix controller pushes the policy to the spoke gateway.
4. The spoke gateway enforces FQDN-based egress: permitted domains pass, everything else is dropped and logged.

Azure IP masquerade is disabled for all pod traffic so the spoke gateway sees original pod IPs. SmartGroups resolve pod identities via Kubernetes label selectors, enabling per-pod enforcement without sidecars.

## Scope and Limitations

- **Supported MCP runtimes:** `npx`, `uvx`, and containerized servers only. Stdio-mode servers are not covered.
- **Protocol and port:** Enforcement applies to HTTPS egress on TCP 443 only. MCP servers requiring non-443 outbound connections are not protected by this feature.
- **Remote MCP servers:** Out of scope. This feature applies only to Kubernetes-hosted MCP servers deployed by Obot. Remote (SSE/HTTP) MCP server connections are not subject to these policies.
- **Domain format:** `egressDomains` entries must be bare hostnames. No protocols (`https://`), paths, ports, or IP addresses. `localhost` and `*.svc` cluster-local names are rejected by Obot at admission. Wildcard prefix notation is supported (e.g., `*.anthropic.com`).
- **Obot-specific domains are scoped to obot-system pods via /32 CIDRs.** The blueprint uses `var.obot_system_pod_cidrs` (list of `/32` CIDRs for obot-system pods) as the source selector for a dedicated V1 permit rule covering `api.anthropic.com`, GitHub, and `charts.obot.ai`. MCP server pods in `obot-mcp` do not match this rule and cannot reach those domains unless declared in `egressDomains`. **Update `obot_system_pod_cidrs` when obot-system pods restart:** pod IPs change and the SmartGroup must be re-applied. Underlying limitation: Aviatrix V1 policy list only supports CIDR SmartGroups as source; k8s namespace SmartGroups are only valid in `K8S_POLICY_LIST`. Per-namespace scoping via `/32` CIDRs is the current workaround.
- **`npx` runtime servers require `registry.npmjs.org` in `egressDomains`.** The npx shim downloads the package from npm at pod startup. This download is subject to the same FirewallPolicy enforcement as all other egress. A server deployed without `registry.npmjs.org` in its `egressDomains` will have its `mcp` container fail (package download blocked) while the `shim` container stays running. Add `registry.npmjs.org` to `egressDomains` for any npx-runtime server. This is intentional: zero-trust requires explicit declaration of every outbound dependency, including package registries.
- **Azure node telemetry (`dc.services.visualstudio.com`) is intentionally blocked.** AKS nodes emit Application Insights telemetry to this endpoint. The default POST_RULES deny catches it because it is not in the infrastructure permit list; by design. AKS functions correctly without it. This is the correct zero-trust posture: every outbound flow that is not explicitly required and permitted is denied, including vendor telemetry. Adding it to the allowlist would undermine the enforcement boundary the blueprint is designed to demonstrate.

## Prerequisites

### Required Tools

- [Aviatrix Control Plane](../../docs/prerequisites/aviatrix-controller.md) (v8.2+) with CoPilot; Controller and CoPilot public IPs required
- [Terraform](../../docs/prerequisites/terraform.md) (v1.5+)
- [Azure CLI](../../docs/prerequisites/azure-cli.md), authenticated (`az login`)
- [kubectl](../../docs/prerequisites/kubectl.md), configured for your cluster
- **Python 3** — required by `local-exec` provisioners for JSON parsing (`curl | python3 -c`)

### Required Access

- Azure subscription with permissions to create resource groups, VNets, subnets, route tables, and AKS clusters
- Aviatrix Controller with an Azure access account (`arm_account_name`) already onboarded
- `Contributor` role on the target Azure subscription

### Blueprint-Specific Requirements

- Obot >= 0.21.0 (the MCPNetworkPolicy egress provider was introduced in this release)
- `spoke_gateway_subnet_cidr` must not overlap `aks_subnet_cidr` or `vnet_address_space` sub-ranges used by other resources

## Resources Created

| Resource | Description | Quantity |
|----------|-------------|----------|
| Azure Resource Group | Contains all created resources | 1 |
| Azure Virtual Network | VNet for AKS nodes and spoke gateway | 1 |
| Azure Subnet | AKS node subnet (Azure CNI, pod IPs from VNet) | 1 |
| Azure Subnet | Aviatrix spoke gateway subnet | 1 |
| Azure Route Table | Public RT for spoke gateway subnet | 1 |
| Azure Route Table | Private RT for AKS node subnet (routes pod egress via spoke) | 1 |
| Azure Kubernetes Cluster | AKS cluster with Azure CNI | 1 |
| Azure Role Assignment | Network Contributor for AKS identity on resource group | 1 |
| Aviatrix Spoke Gateway | DCF-enforced egress gateway (no transit required) | 1 |
| Aviatrix Kubernetes Cluster | AKS onboarding for pod identity resolution | 1 |
| Aviatrix SmartGroup | MCP server pods (by namespace) | 1 |
| Aviatrix SmartGroup | AKS node subnet CIDR | 1 |
| Aviatrix SmartGroup | K8s API server public IP | 1 |
| Aviatrix SmartGroup | obot-system pod /32 CIDRs | 1 |
| Aviatrix WebGroup | AKS infrastructure egress domains | 1 |
| Aviatrix WebGroup | Obot application domains (Anthropic, GitHub) | 1 |
| Aviatrix DCF Policy List | V1 infrastructure permits | 1 |
| Aviatrix DCF Default Action | Deny-all at POST_RULES level | 1 |
| Kubernetes ConfigMap | Azure ip-masq-agent config (disables pod SNAT) | 1 |
| Kubernetes Namespace | Obot system namespace | 1 |
| Kubernetes Namespace | Obot MCP server namespace | 1 |
| Helm Release | Obot platform (includes aviatrix-network-policy-controller) | 1 |

**Estimated Cost**: ~$0.15–0.25/hour for the spoke gateway VM (Standard_B2ms) plus AKS node costs (~$0.10–0.20/hour for Standard_D4s_v3 at 2 nodes).

## Deployment

### Step 1: Clone and Navigate

```bash
git clone https://github.com/AviatrixSystems/aviatrix-blueprints.git
cd aviatrix-blueprints/blueprints/obot-mcp-egress-azure
```

### Step 2: Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`. All fields marked `REQUIRED` must be set.

### Step 3: Deploy

```bash
terraform init
terraform plan
terraform apply
```

Deployment takes approximately 15–20 minutes (spoke gateway provisioning is the longest step).

### Step 4: Enable K8s Enforcement in CoPilot

These two settings must be enabled manually after first deploy (controller UI only):

1. **DCF Kubernetes Enforcement**: CoPilot → DCF → Settings → Enforcement on Kubernetes → Enable
2. **Log Enrichment** (for pod-level FlowIQ identity): CoPilot → Feature Previews → Log Enrichment → Enable

### Step 5: Verify Deployment

```bash
# Check Terraform outputs
terraform output

# Verify Obot is running
kubectl get pods -n obot-system

# Port-forward Obot UI (access at http://localhost:8080)
kubectl port-forward -n obot-system svc/obot-obot 8080:80
```

## Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `azure_subscription_id` | Azure subscription ID | `string` | n/a | yes |
| `azure_location` | Azure region (e.g. `"UK South"`) | `string` | n/a | yes |
| `controller_ip` | Aviatrix Controller IP or hostname | `string` | n/a | yes |
| `controller_username` | Controller admin username | `string` | `"admin"` | no |
| `controller_password` | Controller admin password | `string` | n/a | yes |
| `arm_account_name` | Azure access account name onboarded in Controller | `string` | n/a | yes |
| `copilot_private_ip` | CoPilot private IP (syslog) | `string` | n/a | yes |
| `copilot_public_ip` | CoPilot public IP (OTEL/DCF Monitor) | `string` | n/a | yes |
| `resource_group_name` | Name of Azure resource group to create | `string` | `"obot-mcp-rg"` | no |
| `vnet_address_space` | VNet address space | `string` | `"10.1.0.0/16"` | no |
| `aks_subnet_cidr` | CIDR for AKS node subnet | `string` | `"10.1.0.0/20"` | no |
| `aks_vm_size` | Azure VM size for AKS nodes | `string` | `"Standard_D4s_v3"` | no |
| `aks_node_count` | Number of AKS nodes | `number` | `2` | no |
| `aks_service_cidr` | CIDR for K8s services (must not overlap VNet) | `string` | `"172.16.0.0/17"` | no |
| `aks_dns_service_ip` | K8s DNS service IP (must be within `aks_service_cidr`) | `string` | `"172.16.0.10"` | no |
| `spoke_gateway_subnet_cidr` | Subnet CIDR for Aviatrix spoke gateway | `string` | `"10.1.200.0/26"` | no |
| `spoke_gateway_size` | Azure VM size for spoke gateway | `string` | `"Standard_B2ms"` | no |
| `obot_version` | Obot Helm chart version (>= 0.21.0) | `string` | `"0.21.0"` | no |
| `npc_chart_version` | aviatrix-network-policy-controller chart version | `string` | `"v0.0.1"` | no |
| `obot_admin_password` | Obot admin password | `string` | n/a | yes |
| `obot_namespace` | Kubernetes namespace for Obot | `string` | `"obot-system"` | no |
| `obot_mcp_namespace` | Kubernetes namespace for MCP server pods | `string` | `"obot-mcp"` | no |
| `obot_system_pod_cidrs` | /32 CIDRs for obot-system pods (two-step deploy) | `list(string)` | `[]` | no |
| `name_prefix` | Prefix for all created resource names | `string` | `"obot-mcp"` | no |
| `copilot_syslog_index` | Remote syslog index slot on the Controller (0-9); must be free | `number` | `9` | no |

## Outputs

| Output | Description |
|--------|-------------|
| `spoke_gateway_name` | Name of the deployed Aviatrix spoke gateway |
| `spoke_gateway_public_ip` | Public IP of the spoke gateway (all pod egress SNATs to this) |
| `obot_namespace` | Kubernetes namespace where Obot is deployed |
| `obot_mcp_namespace` | Kubernetes namespace where Obot deploys MCP server pods |
| `next_steps` | Post-deployment instructions |

## Test Scenarios

### Scenario 1: Verify Default Deny

Confirm that a newly deployed MCP server with no `egressDomains` configured has no outbound access:

```bash
# Get the MCP server pod name (replace <server-name> as appropriate)
kubectl get pods -n obot-mcp -l app=<server-name>

# Attempt an outbound connection from inside the pod
kubectl exec -n obot-mcp <pod-name> -- curl -s --max-time 5 https://api.openai.com

# Expected result: connection times out (blocked by DCF default deny)
```

Check CoPilot → DCF → Monitor to see the denied flow logged.

### Scenario 2: Configure egressDomains and Verify Allow

`MCPNetworkPolicy` is an internal Obot concept; there is no user-facing Kubernetes CRD to apply.
Configure `egressDomains` via the Obot API or UI. Obot creates the MCPNetworkPolicy internally;
the `aviatrix-network-policy-controller` reconciles it into a `FirewallPolicy` CRD.

```bash
# Update the MCP server to allow specific egress domains (replace <server-id>)
curl -X PUT http://localhost:8080/api/mcp-servers/<server-id> \
  -H "Content-Type: application/json" \
  -d '{
    "manifest": {
      "name": "my-server",
      "runtime": "npx",
      "npxConfig": {
        "package": "@modelcontextprotocol/server-github",
        "egressDomains": ["api.openai.com"]
      }
    }
  }'

# Verify the FirewallPolicy CRD was created or updated
kubectl get firewallpolicies -n obot-mcp

# Retry the outbound connection (no sleep needed; policy exists before pod starts)
kubectl exec -n obot-mcp <pod-name> -- curl -s --max-time 10 https://api.openai.com

# Expected result: connection succeeds
```

> **Note:** The `aviatrix-network-policy-controller` creates the FirewallPolicy at server-definition
> time, not at launch time. By the time the pod starts, the policy is already enforced.
> See `k8s/example-mcpnetworkpolicy.yaml` for the shape of the generated `FirewallPolicy`.

### Scenario 3: Verify Unlisted Domain is Blocked

```bash
# This domain is not in the egressDomains allowlist
kubectl exec -n obot-mcp <pod-name> -- curl -s --max-time 5 https://example.com

# Expected result: connection times out (blocked by DCF, not in approved domains)
```

## Cleanup

```bash
terraform destroy
```

If destroy fails, manually delete the Azure Route Table associations before retrying:

```bash
az network vnet subnet update \
  --name <aks-subnet-name> \
  --vnet-name <vnet-name> \
  --resource-group <vnet-rg> \
  --remove routeTable
```

## Troubleshooting

### Spoke gateway creation fails or times out

Verify the gateway subnet is correctly classified as public:

```bash
az network route-table show \
  --name <name_prefix>-rt-avx-gw \
  --resource-group <vnet_resource_group> \
  --query routes
```

The `default-Internet` route with `nextHopType: Internet` must be present.

### DCF Monitor is empty but FlowIQ works

The spoke gateway OTEL exporter is not reaching CoPilot. This happens when `copilot_public_ip` is wrong or missing. Verify:

```bash
terraform output spoke_gateway_public_ip
# This IP must be permitted in the CoPilot NSG for TCP 31284 inbound.
```

### egressDomains configured but traffic still blocked

1. Verify DCF Kubernetes Enforcement is enabled in CoPilot → DCF → Settings.
2. Check the feature flags were applied: `terraform apply` re-runs the `k8s_dcf_features` provisioner on each apply.
3. Verify Log Enrichment is enabled (required for SmartGroup pod-label matching).
4. Confirm a `FirewallPolicy` exists for the server: `kubectl get firewallpolicies -n obot-mcp`
5. Check pod labels match the FirewallPolicy selector: `kubectl get pod <pod-name> -n obot-mcp --show-labels`

### SmartGroups show workload_type as VM instead of k8s

Log Enrichment is not enabled. Enable it in CoPilot → Feature Previews → Log Enrichment.

## Tested With

| Component | Version |
|-----------|---------|
| Aviatrix Controller | 8.2.x |
| Aviatrix Terraform Provider | 8.2.0 |
| Terraform | 1.9.x |
| AzureRM Provider | 3.116.x |
| Obot | 0.21.0 |

## Built With

This blueprint was developed by [Nick Davitashvili](https://github.com/nickda) (Aviatrix) in collaboration with [Grant Linville](https://github.com/g-linville) (Obot AI), who built the MCPNetworkPolicy egress provider in Obot.

## Contributing

See the [Contributing Guide](../../CONTRIBUTING.md) for information on how to contribute to this blueprint.

## License

Apache 2.0. See [LICENSE](../../LICENSE)
