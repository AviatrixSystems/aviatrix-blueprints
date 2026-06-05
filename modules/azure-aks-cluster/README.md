> **AZURE MODULE — mirrors `modules/aws-eks-cluster/` for Azure.** The design intent, variable taxonomy, and output names track the AWS module. Azure-specific differences (the system node pool lives inline in `azurerm_kubernetes_cluster` rather than in a separate node-group module, Azure CNI pod-subnet mode + Cilium instead of AWS VPC CNI custom networking, workload identity instead of IRSA) are documented below. Changes to shared behaviour should be reflected in both modules.

# azure-aks-cluster

Terraform module that provisions a single AKS cluster shaped for Aviatrix Distributed Cloud Firewall (DCF) egress filtering, with the system node pool inline, workload identity enabled, and optional Aviatrix Controller onboarding for Kubernetes-typed SmartGroups.

## What this module creates

- **User-assigned managed identity** for the AKS control plane.
- **Three role assignments** (all `Network Contributor`) granting the AKS identity rights over:
  - the spoke VNet (`var.vnet_id`) — to manage NICs and internal load balancers,
  - the node route table (`var.node_route_table_id`),
  - the pod route table (`var.pod_route_table_id`).
- **AKS cluster** (`azurerm_kubernetes_cluster`) with:
  - **Inline system node pool** (`default_node_pool`) — Azure requires the node pool be declared in the cluster, so unlike the AWS module there is no separate node-group module. Autoscaling is enabled, `max_pods = 250`, and `node_count` drift is ignored.
  - **OIDC issuer + workload identity** enabled (the Azure equivalent of AWS IRSA).
  - **Azure CNI pod-subnet mode + Cilium** (`network_plugin = "azure"`, `network_policy = "cilium"`, `network_data_plane = "cilium"`). Pods get real VNet addresses from `var.pod_subnet_id`, so packets reach the Aviatrix spoke gateway with their original pod IP (no node-level SNAT).
  - **`outbound_type = "userDefinedRouting"`** — all egress follows the controller-programmed `0.0.0.0/0 → spoke GW` route on the node and pod route tables (programmed by the network layer / `azure-aks-spoke-vnet` module).
  - **API server authorized IP ranges** = `var.authorized_ip_ranges` + the spoke gateway public IP + (when onboarding) the controller public IP. The spoke GW public IP is mandatory: nodes egress through it, so the kubelet CSE bootstrap fails without it.
- **Aviatrix Kubernetes cluster onboarding** (`aviatrix_kubernetes_cluster`), gated by `var.enable_aviatrix_onboarding`.

## Egress / SNAT design

This cluster is designed to sit behind an Aviatrix spoke gateway using the 9.0 Single IP SNAT explicit-route-table-selection feature (see `modules/azure-aks-spoke-vnet`). Pod IPs come from a dedicated VNet subnet (pod-subnet mode), so Azure routes pod packets natively to the spoke gateway where DCF inspection and SNAT occur.

```
Pod / Node (VNet IP) → UDR 0.0.0.0/0 → Aviatrix Spoke GW → DCF inspect → Single IP SNAT → Internet
```

## Aviatrix Controller onboarding requirement

When `enable_aviatrix_onboarding = true`, the controller fetches a kubeconfig from the AKS cluster and connects to the API server. This imposes requirements **not enforced by Terraform** (pre-checks for the operator):

- The Aviatrix Azure access account's service principal must have `Microsoft.ContainerService/managedClusters/listClusterUserCredential/action` at subscription scope (Contributor includes it). The controller calls ARM `listClusterUserCredential` to obtain a **local-account kubeconfig**.
- The cluster **must use Kubernetes RBAC with local accounts**. **Entra-ID-only auth is NOT supported** — the returned kubeconfig would contain `exec` entries the controller cannot process.
- The controller's public egress IP must be in the AKS API server's `authorized_ip_ranges`. Set `aviatrix_controller_public_ip` so it is appended automatically.

## Requirements

- **Aviatrix Controller / CoPilot 9.0+** (matches the `aviatrix ~> 9.0` provider pin and the spoke module's Single IP SNAT route-table selection).
- Providers: `azurerm ~> 4.0`, `aviatrix ~> 9.0`. This module declares only `required_providers`; provider configuration is supplied by the consuming blueprint layer.

## Usage

```hcl
module "cluster" {
  source = "../../../modules/azure-aks-cluster"

  cluster_name        = "aks-single"
  azure_region        = "eastus2"
  resource_group_name = module.spoke_vnet.resource_group_name

  vnet_id             = module.spoke_vnet.vnet_id
  node_subnet_id      = module.spoke_vnet.node_subnet_id
  pod_subnet_id       = module.spoke_vnet.pod_subnet_id
  node_route_table_id = module.spoke_vnet.node_route_table_id
  pod_route_table_id  = module.spoke_vnet.pod_route_table_id

  kubernetes_version = "1.33"
  node_pool_config = {
    node_count = 2
    min_count  = 1
    max_count  = 3
    vm_size    = "Standard_B2s"
  }

  service_cidr   = "172.16.0.0/16"
  dns_service_ip = "172.16.0.10"

  authorized_ip_ranges    = ["0.0.0.0/0"]
  spoke_gateway_public_ip = module.spoke_vnet.spoke_gateway_public_ip

  enable_aviatrix_onboarding    = true
  aviatrix_controller_public_ip = "x.x.x.x"

  tags = {
    Environment = "demo"
    Blueprint   = "azure-aks-singlecluster"
  }
}
```

## Post-deployment

Fetch kubeconfig (also surfaced as the `configure_kubectl` output):

```bash
az aks get-credentials --resource-group <rg> --name <cluster_name>
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `cluster_name` | AKS cluster name. | `string` | — | yes |
| `azure_region` | Azure region (azurerm form, e.g. `eastus2`). | `string` | — | yes |
| `resource_group_name` | Resource group to create the AKS cluster in (the spoke VNet's RG). | `string` | — | yes |
| `vnet_id` | Spoke VNet resource ID (for the AKS identity Network Contributor role). | `string` | — | yes |
| `node_subnet_id` | Subnet ID for AKS node VMs. | `string` | — | yes |
| `pod_subnet_id` | Subnet ID for AKS pods (pod-subnet mode). | `string` | — | yes |
| `node_route_table_id` | Node route table ID (for the AKS identity Network Contributor role). | `string` | — | yes |
| `pod_route_table_id` | Pod route table ID (for the AKS identity Network Contributor role). | `string` | — | yes |
| `kubernetes_version` | AKS Kubernetes version. | `string` | `"1.33"` | no |
| `node_pool_config` | System/user node pool sizing (`node_count`, `min_count`, `max_count`, `vm_size`). | `object` | `{ node_count = 2, min_count = 1, max_count = 3, vm_size = "Standard_B2s" }` | no |
| `service_cidr` | Kubernetes service CIDR (must not overlap VNet or pod CIDR). | `string` | `"172.16.0.0/16"` | no |
| `dns_service_ip` | Kubernetes DNS service IP (within `service_cidr`). | `string` | `"172.16.0.10"` | no |
| `authorized_ip_ranges` | Extra CIDRs allowed to reach the AKS API server. The spoke GW public IP and (optionally) controller IP are appended automatically. | `list(string)` | `["0.0.0.0/0"]` | no |
| `spoke_gateway_public_ip` | Spoke gateway public IP, appended to AKS API `authorized_ip_ranges` so node CSE bootstrap succeeds. | `string` | — | yes |
| `enable_aviatrix_onboarding` | Register the AKS cluster with the Aviatrix Controller for K8s SmartGroups. | `bool` | `true` | no |
| `aviatrix_controller_public_ip` | Controller public egress IP, appended to AKS API `authorized_ip_ranges` when onboarding. | `string` | `null` | no |
| `tags` | Tags applied to created resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description | Sensitive |
|------|-------------|:---------:|
| `cluster_id` | AKS cluster resource ID. | no |
| `cluster_name` | AKS cluster name. | no |
| `oidc_issuer_url` | OIDC issuer URL (for workload identity federation). | no |
| `kubelet_identity_object_id` | Object ID of the kubelet managed identity. | no |
| `host` | AKS API server host. | yes |
| `client_certificate` | Kubeconfig client certificate. | yes |
| `client_key` | Kubeconfig client key. | yes |
| `cluster_ca_certificate` | Kubeconfig cluster CA certificate. | yes |
| `configure_kubectl` | `az aks get-credentials` command to fetch kubeconfig. | no |
