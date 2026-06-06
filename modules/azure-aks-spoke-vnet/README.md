> **AZURE MODULE — mirrors `modules/aws-eks-spoke-vpc/` for Azure.** The design intent, variable taxonomy, and output names track the AWS module. Azure-specific differences (UDR route tables instead of AWS route tables, `private_route_table_config` instead of `lifecycle`-only route management, `vpc_id` as `vnet_name:rg:guid`) are documented below. Changes to shared behaviour should be reflected in both modules.

# azure-aks-spoke-vnet

Terraform module that provisions a "spoke-in-a-box" Azure VNet shaped for AKS workloads and wired with an Aviatrix spoke gateway using the Aviatrix 9.0 Single IP SNAT explicit-route-table-selection feature.

## What this module creates

- **Resource group** containing all spoke resources.
- **VNet** with two address spaces: a routable `/23` (for gateway, ingress, and node subnets) and a dedicated pod CIDR (for Azure CNI pod-subnet mode).
- **Four subnets:**
  - `<name>-avx-gw` `/28` — Aviatrix spoke gateway (carved as `cidrsubnet(vnet_cidr, 5, 0)`).
  - `<name>-ingress` `/25` — Internal NGINX load balancer (carved as `cidrsubnet(vnet_cidr, 2, 1)`).
  - `<name>-node` `/24` — AKS node pool VMs (carved as `cidrsubnet(vnet_cidr, 1, 1)`).
  - `<name>-pod` — Full pod CIDR address space; AKS allocates pod IPs here in pod-subnet mode.
- **Four route tables** (one per subnet), all with `lifecycle { ignore_changes = [route] }` so Aviatrix controller-programmed routes survive re-apply.
- **Route table associations** linking each subnet to its route table.
- **Aviatrix spoke gateway** (via `terraform-aviatrix-modules/mc-spoke/aviatrix` 9.0.0) with `single_ip_snat = true` and `private_route_table_config` pointing at the node and pod route tables.

## Single IP SNAT + `private_route_table_config` design

Aviatrix 9.0 introduced `private_route_table_config` on the mc-spoke module for Azure. It tells the Aviatrix Controller which route tables to program with `0.0.0.0/0 → spoke gateway` after the gateway comes up.

**Only the node and pod route tables are included.** The gateway and ingress route tables are deliberately excluded:

| Route table | In `private_route_table_config`? | Reason |
|---|---|---|
| `<name>-gateway-rt` | No | Loop avoidance: the spoke GW lives in this subnet. |
| `<name>-ingress-rt` | No | Symmetric return path: the internal NGINX LB must reply directly to clients inside the VNet, not via the spoke GW. |
| `<name>-node-rt` | Yes | All node egress (kubelet, system daemons, internet) flows through the GW for DCF inspection + SNAT. |
| `<name>-pod-rt` | Yes | All pod egress flows through the GW; pod CIDRs (100.64.0.0/16) are SNAT'd to the GW private IP before leaving the VNet. |

The result is Single IP SNAT: every pod and node appears to the internet as the spoke gateway's single public IP, without requiring a custom `aviatrix_gateway_snat` resource.

## Requirements

| Tool | Version |
|---|---|
| Terraform | >= 1.7 |
| Aviatrix provider | ~> 9.0 |
| Azure provider | ~> 4.0 |
| mc-spoke module | 9.0.0 |
| **Aviatrix Controller** | **9.0+** (required for `private_route_table_config` and Single IP SNAT on Azure) |

## Variables

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `name` | `string` | — | yes | Base name for the spoke VNet, resource group, and gateway. |
| `cluster_name` | `string` | — | yes | AKS cluster name, used for subnet/resource tagging. |
| `vnet_cidr` | `string` | `"10.30.0.0/23"` | no | Routable /23 CIDR for the VNet (gateway, ingress, node subnets carved from this). |
| `pod_cidr` | `string` | `"100.64.0.0/16"` | no | Dedicated pod subnet CIDR (Azure CNI pod-subnet mode), added as a 2nd VNet address space. |
| `azure_region` | `string` | — | yes | Azure region in azurerm form (e.g. `eastus2`). |
| `aviatrix_azure_region` | `string` | — | yes | Azure region in Aviatrix form (e.g. `East US 2`). Both forms are required because the azurerm and Aviatrix providers use different formats. |
| `aviatrix_azure_account_name` | `string` | — | yes | Name of the Azure access account onboarded in the Aviatrix Controller. |
| `transit_type` | `string` | `"none"` | no | `"none"` = standalone (Single IP SNAT egress only); `"aviatrix"` = attach to an Aviatrix transit gateway. |
| `transit_gw_name` | `string` | `""` | aviatrix only | Aviatrix transit gateway name to attach to. Required when `transit_type = "aviatrix"`. |
| `tags` | `map(string)` | `{}` | no | Tags applied to created resources. |

## Outputs

| Output | Description |
|---|---|
| `resource_group_name` | Resource group containing the spoke VNet. |
| `vnet_id` | Azure resource ID of the spoke VNet. |
| `vnet_name` | Name of the spoke VNet. |
| `aviatrix_vpc_id` | Aviatrix `vpc_id` form: `vnet_name:resource_group:guid`. Required when referencing the spoke in other Aviatrix resources. |
| `gateway_subnet_id` | Subnet ID of the Aviatrix gateway subnet. |
| `ingress_subnet_id` | Subnet ID of the ingress subnet (internal NGINX LB). |
| `ingress_subnet_name` | Name of the ingress subnet (used by Helm ingress-nginx annotations). |
| `node_subnet_id` | Subnet ID for AKS node VMs. |
| `pod_subnet_id` | Subnet ID for AKS pods (pod-subnet mode). |
| `node_route_table_id` | Node route table ID (used for AKS identity Network Contributor role assignment). |
| `pod_route_table_id` | Pod route table ID (used for AKS identity Network Contributor role assignment). |
| `spoke_gateway_name` | Name of the Aviatrix spoke gateway. |
| `spoke_gateway_public_ip` | Public IP of the spoke gateway. Pass to `authorized_ip_ranges` in the AKS cluster so node CSE bootstrap succeeds. |
| `spoke_gateway_private_ip` | Private IP of the spoke gateway (sensitive). |
| `spoke_gateway` | Full Aviatrix spoke gateway object from mc-spoke (sensitive; for advanced callers). |

## Usage example: standalone (Single IP SNAT egress)

```hcl
module "spoke_vnet" {
  source = "../../modules/azure-aks-spoke-vnet"

  name         = "aks-single"
  cluster_name = "aks-single"
  vnet_cidr    = "10.30.0.0/23"
  pod_cidr     = "100.64.0.0/16"

  azure_region          = "eastus2"
  aviatrix_azure_region = "East US 2"

  aviatrix_azure_account_name = "Azure"

  # Default: standalone — no transit attachment.
  # transit_type    = "none"
  # transit_gw_name = ""

  tags = {
    Environment = "demo"
    Blueprint   = "azure-aks-singlecluster"
  }
}
```

## Usage example: attached to an Aviatrix transit

```hcl
module "spoke_vnet" {
  source = "../../modules/azure-aks-spoke-vnet"

  name         = "aks-single"
  cluster_name = "aks-single"
  vnet_cidr    = "10.30.0.0/23"

  azure_region          = "eastus2"
  aviatrix_azure_region = "East US 2"

  aviatrix_azure_account_name = "Azure"

  transit_type    = "aviatrix"
  transit_gw_name = "avx-transit-eastus2"

  tags = { Environment = "demo" }
}
```

## Region name duality

Azure requires two region name formats that differ between providers:

| Format | Example | Used by |
|---|---|---|
| `azure_region` (azurerm) | `"eastus2"` | `azurerm_resource_group`, `azurerm_virtual_network`, etc. |
| `aviatrix_azure_region` (Aviatrix) | `"East US 2"` | mc-spoke `region` argument, Aviatrix Controller API |

Always supply both. A mismatch causes the spoke gateway to be deployed in a different region than the VNet.

## Pod subnet delegation drift

AKS automatically attaches a `Microsoft.ContainerService/managedClusters` delegation to the pod subnet when the cluster starts in pod-subnet mode. The `lifecycle { ignore_changes = [delegation] }` block on `azurerm_subnet.pod` prevents Terraform from removing this delegation on subsequent applies (Azure rejects the removal with `SubnetMissingRequiredDelegation` while AKS holds the service association link).

When destroying, delete the AKS cluster before running `terraform destroy` on this module. If `terraform destroy` still fails on the pod subnet, use `-target` to destroy all other resources first:

```bash
terraform destroy -target=module.spoke -target=azurerm_subnet_route_table_association.pod
# Then after AKS is fully gone:
terraform destroy
```
