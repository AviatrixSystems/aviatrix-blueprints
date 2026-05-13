# Zero-Trust MCP Egress: Obot on EKS with Aviatrix DCF

Deploy [Obot](https://obot.ai) onto a new EKS cluster with network-layer zero-trust egress enforcement for all MCP server pods. An Aviatrix spoke gateway intercepts outbound traffic; MCPNetworkPolicy CRDs (reconciled by Obot's bundled aviatrix-network-policy-controller) translate per-server allowlists into live FirewallPolicy rules. No sidecars, no service mesh, no code changes required.

## Architecture

![Architecture Diagram](architecture.svg)

Architecture diagram coming soon.

Traffic flow:

1. Obot user creates an MCP server and configures its allowed egress domains via the Obot UI or API.
2. Obot's bundled `aviatrix-network-policy-controller` reconciles the server's `MCPNetworkPolicy` into an Aviatrix `FirewallPolicy` CRD.
3. The Aviatrix controller pushes the policy to the spoke gateway.
4. The spoke gateway enforces FQDN-based egress: permitted domains pass, everything else is dropped and logged.

The vpc-cni addon is configured with `EXTERNALSNAT=true`, which disables per-node SNAT and ensures the spoke gateway sees original pod IPs. SmartGroups resolve pod identities via Kubernetes label selectors; however, see the EKS Limitation section below.

## Scope and Limitations

- **Supported MCP runtimes:** `npx`, `uvx`, and containerized servers only. Stdio-mode servers are not covered.
- **Protocol and port:** Enforcement applies to HTTPS egress on TCP 443 only. MCP servers requiring non-443 outbound connections are not protected by this feature.
- **Remote MCP servers:** Out of scope. This feature applies only to Kubernetes-hosted MCP servers deployed by Obot. Remote (SSE/HTTP) MCP server connections are not subject to these policies.
- **Domain format:** `egressDomains` entries must be bare hostnames. No protocols (`https://`), paths, ports, or IP addresses. `localhost` and `*.svc` cluster-local names are rejected by Obot at admission. Wildcard prefix notation is supported (e.g., `*.anthropic.com`).
- **EKS known limitation: K8s label-based SmartGroups register as Partial.** The Aviatrix controller registers EKS clusters as Partial (assetd watcher subscriptions lost on controller restart; custom resource watchers return 404). K8s namespace SmartGroups cannot be used as V1 policy sources for per-pod enforcement. **Workaround:** `obot_system_pod_cidrs` and `obot_mcp_pod_cidrs` take lists of `/32` CIDRs corresponding to running pods. These drive V1 CIDR-based SmartGroups that enforce correctly. **You must update these variables after any pod restart.** See the two-step and three-step deploy procedures below. This is a platform limitation pending an upstream fix; the CIDR workaround is the current supported path.
- **Obot-specific domains are scoped to obot-system pods via /32 CIDRs.** `var.obot_system_pod_cidrs` drives a dedicated V1 permit rule covering `api.anthropic.com`, GitHub, and `charts.obot.ai`. MCP server pods in `obot-mcp` do not match this rule and cannot reach those domains unless declared in `egressDomains`.
- **`npx` runtime servers require `registry.npmjs.org` in `egressDomains`.** The npx shim downloads the package from npm at pod startup. A server deployed without `registry.npmjs.org` in its `egressDomains` will have its `mcp` container fail (package download blocked) while the `shim` container stays running. This is intentional: zero-trust requires explicit declaration of every outbound dependency, including package registries.
- **Node bootstrap requires spoke gateway routes first.** `node_desired_size` defaults to `0`. EKS nodes that start before the Aviatrix spoke gateway programs the VPC route tables fail to bootstrap (CSE exit 50, unreachable API server). Scale up after first apply using the command in the `next_steps` output.

## Prerequisites

### Required Tools

- [Aviatrix Control Plane](../../docs/prerequisites/aviatrix-controller.md) (v8.2+) with CoPilot; Controller and CoPilot public IPs required
- [Terraform](../../docs/prerequisites/terraform.md) (v1.5+)
- [AWS CLI](../../docs/prerequisites/aws-cli.md), authenticated (`aws configure` or equivalent)
- [kubectl](../../docs/prerequisites/kubectl.md), configured for your cluster (EKS authentication uses the AWS CLI exec plugin)
- **Python 3** — required by `local-exec` provisioners for JSON parsing (`curl | python3 -c`)

### Required Access

- AWS account with permissions to create VPCs, subnets, IAM roles, EKS clusters, and managed node groups
- Aviatrix Controller with an AWS access account (`aws_access_account`) already onboarded
- IAM permissions: `eks:*`, `ec2:*`, `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PassRole`

### Blueprint-Specific Requirements

- Obot >= 0.21.0 (the MCPNetworkPolicy egress provider was introduced in this release)
- `vpc_cidr` must not overlap any existing VPCs in the same region if you plan to peer or connect them later
- AWS CLI must be installed and on `PATH`; kubectl uses it as the exec credential plugin for EKS

## Resources Created

| Resource | Description | Quantity |
|----------|-------------|----------|
| AWS VPC | VPC for EKS nodes and spoke gateway | 1 |
| AWS Subnet (private) | EKS node subnets, one per AZ (/24 each) | 3 |
| AWS Subnet (public) | Aviatrix spoke gateway subnet (/24) | 1 |
| AWS Internet Gateway | Provides outbound path for spoke gateway | 1 |
| AWS Route Table | Public RT for spoke gateway subnet | 1 |
| AWS Route Table | Private RT for EKS node subnets (routes pod egress via spoke) | 1 |
| EKS Cluster | EKS cluster with vpc-cni (EXTERNALSNAT=true) | 1 |
| EKS Managed Node Group | EC2 managed node group (scaled to 0 on first apply) | 1 |
| IAM Role | vpc-cni IRSA role (EXTERNALSNAT=true requires IRSA) | 1 |
| aws_eks_addon (vpc-cni) | Manages pod networking with EXTERNALSNAT=true | 1 |
| Aviatrix Spoke Gateway | DCF-enforced egress gateway (no transit required) | 1 |
| Aviatrix Kubernetes Cluster | EKS onboarding for pod identity resolution (Partial on EKS) | 1 |
| Aviatrix SmartGroup | MCP server pods (K8s label selector, Partial on EKS) | 1 |
| Aviatrix SmartGroup | EKS VPC CIDR | 1 |
| Aviatrix SmartGroup | obot-system pod /32 CIDRs | 1 |
| Aviatrix SmartGroup | obot-mcp pod /32 CIDRs (conditional on var) | 1 |
| Aviatrix WebGroup | EKS infrastructure egress domains (ECR, S3, SSM, EC2, EKS endpoints, charts.obot.ai) | 1 |
| Aviatrix WebGroup | Obot application domains (Anthropic, GitHub) | 1 |
| Aviatrix DCF Policy List | V1 infrastructure permits (P1: infra, P2: obot-system, P3: obot-mcp deny conditional) | 1 |
| Aviatrix DCF Default Action | Deny-all at POST_RULES level | 1 |
| CoPilot Association | null_resource to associate spoke with CoPilot | 1 |
| Remote Syslog | Index 9, UDP 5000 to CoPilot private IP | 1 |
| Kubernetes Namespace | Obot system namespace | 1 |
| Kubernetes Namespace | Obot MCP server namespace | 1 |
| Helm Release | Obot platform (embedded SQLite, NPC self-managed) | 1 |

**Estimated Cost**: ~$0.15-0.25/hour for the spoke gateway EC2 instance plus EKS node costs (~$0.10-0.20/hour for m5.large at 2 nodes). EKS control plane: $0.10/hour.

## Deployment

### Step 1: Clone and Navigate

```bash
git clone https://github.com/AviatrixSystems/aviatrix-blueprints.git
cd aviatrix-blueprints/blueprints/obot-mcp-egress-aws
```

### Step 2: Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`. All fields marked `REQUIRED` must be set.

### Step 3: First Apply (node_desired_size=0)

```bash
terraform init
terraform plan
terraform apply
```

`node_desired_size` defaults to `0`. The EKS node group is created but no nodes start. This is intentional: nodes that start before the Aviatrix spoke gateway programs VPC routes fail to bootstrap (EKS API server unreachable, CSE exit 50). The spoke gateway provisions during this apply.

Deployment takes approximately 20-30 minutes (EKS control plane + spoke gateway provisioning are the longest steps).

### Step 4: Scale Up EKS Nodes

After `terraform apply` completes, scale the node group:

```bash
aws eks update-nodegroup-config \
  --cluster-name <cluster-name> \
  --nodegroup-name system \
  --scaling-config minSize=1,maxSize=4,desiredSize=2
```

Use the `eks_cluster_name` output for the cluster name. Wait for nodes to reach `Ready`:

```bash
kubectl get nodes -w
```

### Step 5: Enable K8s Enforcement in CoPilot

These settings must be enabled manually after first deploy (controller UI only):

1. **DCF Kubernetes Enforcement**: CoPilot -> DCF -> Settings -> Enforcement on Kubernetes -> Enable
2. **Log Enrichment** (for pod-level FlowIQ identity): CoPilot -> Feature Previews -> Log Enrichment -> Enable

### Step 6: Populate obot-system Pod CIDRs (Two-Step Deploy)

Once Obot is running, retrieve pod IPs and re-apply to scope egress permits:

```bash
# Get obot-system pod IPs
kubectl get pods -n obot-system -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}'
```

Add those IPs as `/32` CIDRs to `obot_system_pod_cidrs` in `terraform.tfvars`, then re-apply:

```bash
# Example entry in terraform.tfvars:
# obot_system_pod_cidrs = ["10.10.1.45/32", "10.10.2.12/32"]

terraform apply
```

Until this step is complete, obot-system pods reach Anthropic, GitHub, and `charts.obot.ai` via the broader infrastructure permit. After re-apply, only pods matching the `/32` SmartGroup are permitted to those domains.

### Step 7: Verify Deployment

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
| `controller_ip` | Aviatrix Controller IP or hostname | `string` | n/a | yes |
| `controller_username` | Controller admin username | `string` | `"admin"` | no |
| `controller_password` | Controller admin password | `string` | n/a | yes |
| `aws_access_account` | AWS access account name onboarded in Controller | `string` | n/a | yes |
| `copilot_private_ip` | CoPilot private IP (syslog) | `string` | n/a | yes |
| `copilot_public_ip` | CoPilot public IP (OTEL/DCF Monitor) | `string` | n/a | yes |
| `obot_admin_password` | Obot admin password | `string` | n/a | yes |
| `aws_region` | AWS region for all resources | `string` | `"us-east-1"` | no |
| `vpc_cidr` | VPC CIDR block (private subnets are /24 slices; public subnet for spoke GW is /24) | `string` | `"10.10.0.0/16"` | no |
| `cluster_version` | Kubernetes version for the EKS cluster | `string` | `"1.32"` | no |
| `node_instance_type` | EC2 instance type for EKS managed node group | `string` | `"m5.large"` | no |
| `node_desired_size` | Desired node count; set to 0 on first apply | `number` | `0` | no |
| `node_max_size` | Maximum number of EKS nodes | `number` | `4` | no |
| `obot_version` | Obot Helm chart version (>= 0.21.0) | `string` | `"0.21.0"` | no |
| `npc_chart_version` | aviatrix-network-policy-controller chart version | `string` | `"v0.0.1"` | no |
| `obot_namespace` | Kubernetes namespace for Obot | `string` | `"obot-system"` | no |
| `obot_mcp_namespace` | Kubernetes namespace for MCP server pods | `string` | `"obot-mcp"` | no |
| `obot_system_pod_cidrs` | /32 CIDRs for obot-system pods (two-step deploy) | `list(string)` | `[]` | no |
| `obot_mcp_pod_cidrs` | /32 CIDRs for obot-mcp pods (three-step deploy; EKS CIDR workaround) | `list(string)` | `[]` | no |
| `name_prefix` | Prefix for all created resource names | `string` | `"obot-mcp"` | no |
| `copilot_syslog_index` | Remote syslog index slot on the Controller (0-9); must be free | `number` | `9` | no |

## Outputs

| Output | Description |
|--------|-------------|
| `eks_cluster_name` | Name of the deployed EKS cluster |
| `spoke_gateway_name` | Name of the deployed Aviatrix spoke gateway |
| `spoke_gateway_public_ip` | Public IP of the spoke gateway (all pod egress SNATs to this) |
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

Check CoPilot -> DCF -> Monitor to see the denied flow logged.

> **Note:** Per-pod enforcement requires `obot_mcp_pod_cidrs` to be populated with the pod's `/32` CIDR and a `terraform apply` to have been run. Until `obot_mcp_pod_cidrs` is set, the deny-all SmartGroup is not created and enforcement is not active for obot-mcp pods. This is the three-step deploy sequence for the EKS CIDR workaround.

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
> See `k8s-apps/example-mcpnetworkpolicy.yaml` for the shape of the generated `FirewallPolicy`.

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

If destroy hangs, delete LoadBalancer services first:

```bash
kubectl delete svc -n obot-system --all
```

Then retry `terraform destroy`. EKS node group scale-down can take several minutes; the destroy will wait.

## Troubleshooting

### EKS nodes fail to bootstrap (CSE exit 50)

This happens when nodes start before the spoke gateway programs VPC routes. Terminate the affected node instances; EKS will replace them once routes are in place:

```bash
aws ec2 terminate-instances --instance-ids <instance-id>
```

If nodes were started before the first `terraform apply` completed, re-image via the AWS console or wait for the managed node group to replace them automatically.

### Spoke gateway creation fails or times out

Verify the public subnet has an Internet Gateway route:

```bash
aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=<name_prefix>-rt-public" \
  --query 'RouteTables[*].Routes'
```

A `0.0.0.0/0` route with `GatewayId` pointing to an IGW must be present.

### DCF Monitor is empty but FlowIQ works

The spoke gateway OTEL exporter is not reaching CoPilot. This happens when `copilot_public_ip` is wrong or missing. Verify:

```bash
terraform output spoke_gateway_public_ip
# This IP must be permitted in the CoPilot security group for TCP 31284 inbound.
```

### egressDomains configured but traffic still blocked

1. Verify DCF Kubernetes Enforcement is enabled in CoPilot -> DCF -> Settings.
2. Check `obot_mcp_pod_cidrs` is populated with current pod IPs and `terraform apply` has been run.
3. Confirm a `FirewallPolicy` exists for the server: `kubectl get firewallpolicies -n obot-mcp`
4. Verify Log Enrichment is enabled: CoPilot -> Feature Previews -> Log Enrichment.
5. Re-check pod IPs have not changed since last apply (pod restarts change IPs; re-apply required).

### K8s label SmartGroups show "Partial" status

This is expected on EKS. The controller cannot maintain assetd watcher subscriptions for EKS custom resources. The CIDR-based SmartGroups (`obot_system_pod_cidrs`, `obot_mcp_pod_cidrs`) are the active enforcement path. "Partial" status on the label-based SmartGroup does not break enforcement; the CIDR SmartGroups are what the V1 policy rules use.

### kubectl cannot authenticate to the cluster

EKS uses the AWS CLI as a credential exec plugin. Ensure:

1. AWS CLI is installed and on `PATH`.
2. The IAM identity used by the CLI has `eks:DescribeCluster` permission.
3. Run `aws eks update-kubeconfig --name <cluster-name> --region <region>` to refresh the kubeconfig.

## Tested With

| Component | Version |
|-----------|---------|
| Aviatrix Controller | 8.2.x |
| Aviatrix Terraform Provider | 8.2.0 |
| Terraform | 1.9.x |
| AWS Provider | 5.x |
| EKS | 1.32 |
| Obot | 0.21.0 |

## Built With

This blueprint was developed by [Nick Davitashvili](https://github.com/nickda) (Aviatrix) in collaboration with [Grant Linville](https://github.com/g-linville) (Obot AI), who built the MCPNetworkPolicy egress provider in Obot.

## Contributing

See the [Contributing Guide](../../CONTRIBUTING.md) for information on how to contribute to this blueprint.

## License

Apache 2.0. See [LICENSE](../../LICENSE)
