# aws-eks-spoke-vpc

Terraform module that provisions a "spoke-in-a-box" AWS VPC shaped for EKS workloads and wired with an Aviatrix spoke gateway.

## What this module creates

The module builds every layer needed between raw AWS account credentials and a running Aviatrix spoke:

- **VPC** with a primary CIDR and a secondary CIDR for pod networking (VPC CNI custom networking).
- **Four subnet tiers** per availability zone (two AZs, hardcoded):
  - `avx_public` /28 — Aviatrix gateway subnets.
  - `lb_public` /26 — Public load-balancer subnets, tagged `kubernetes.io/role/elb=1`.
  - `infra_private` /26 — EKS node subnets, tagged `kubernetes.io/role/internal-elb=1`.
  - `pod_private` /17 — Pod subnets from the secondary CIDR, consumed by ENIConfig in the nodes layer.
- **Route tables** for each tier (avx_public, lb_public, infra_private, pod_private), all with `lifecycle { ignore_changes = [route] }` so Aviatrix controller-programmed RFC1918 routes survive re-apply.
- **Internet gateway** attached to the public route tables.
- **Aviatrix spoke gateway** (via the `terraform-aviatrix-modules/mc-spoke/aviatrix` module), optionally attached to an Aviatrix transit.
- **Custom SNAT** (aviatrix mode only) so pods using a non-routable overlay CIDR are translated to the spoke gateway private IP before entering the transit fabric.
- **Native-cloud route programming** (aws_tgw / aws_cloudwan mode, when a transit target ID is supplied) with `aws_route` resources on infra_private and pod_private for default + east-west destinations.

## Transit type and pod-CIDR mode matrix

The two most important variables are `transit_type` and `pod_cidr_mode`. Their interaction determines SNAT shape and route-table behavior.

| transit_type | pod_cidr_mode | SNAT | Route programming | Typical use-case |
|---|---|---|---|---|
| `aws_tgw` (default) | `non_routable` (default) | `single_ip_snat = true` on spoke module | Nothing (standalone); or native routes when `aws_tgw_id` is set | Default standalone deployment; TGW attachment wired out-of-band |
| `aws_tgw` | `routable` | `single_ip_snat = true` on spoke module | Pod east-west via TGW (native transit) when `aws_tgw_id` is set | Pod CIDRs are unique per spoke and advertised into TGW |
| `aws_cloudwan` | `non_routable` | `single_ip_snat = true` on spoke module | Nothing (standalone); or native routes when `aws_cloudwan_core_network_arn` is set | Cloud WAN attachment wired out-of-band |
| `aws_cloudwan` | `routable` | `single_ip_snat = true` on spoke module | Pod east-west via Cloud WAN core network when ARN is set | Pod CIDRs unique per spoke, advertised into Cloud WAN |
| `aviatrix` | `non_routable` | Custom `aviatrix_gateway_snat` (3 policies) | Routes programmed by Aviatrix controller post-attach | Full Aviatrix fabric with overlapping pod CIDRs |
| `aviatrix` | `routable` | Custom `aviatrix_gateway_snat` (2 policies, no infra-eth0) | Routes programmed by Aviatrix controller post-attach | Full Aviatrix fabric with unique pod CIDRs |

### Standalone spoke (default)

The default configuration (`transit_type = "aws_tgw"`, empty `aws_tgw_id`) deploys a standalone spoke with `single_ip_snat = true` and programs **no** route entries. The operator wires the TGW attachment and route-table entries out-of-band, then sets `aws_tgw_id` and re-applies to let the module take over route management.

## Variables

| Variable | Type | Default | Required | Description |
|---|---|---|---|---|
| `name` | `string` | — | yes | Name prefix for all resources (e.g. `"frontend"`, `"team-a"`). |
| `cluster_name` | `string` | — | yes | EKS cluster name. Used to tag subnets with `kubernetes.io/cluster/<name>=shared`. |
| `primary_cidr` | `string` | — | yes | Primary VPC CIDR. Subnet math assumes /23 (produces /28 gateway, /26 LB, /26 infra subnets per AZ). |
| `region` | `string` | — | yes | AWS region. AZs are derived as `<region>a` and `<region>b`. |
| `aviatrix_aws_account_name` | `string` | — | yes | AWS account name as registered in the Aviatrix Controller. |
| `pod_cidr` | `string` | `"100.64.0.0/16"` | no | Secondary CIDR for pod networking. May overlap across spokes (SNAT handles translation). |
| `transit_type` | `string` | `"aws_tgw"` | no | Transit connectivity mode: `aviatrix`, `aws_tgw`, or `aws_cloudwan`. |
| `pod_cidr_mode` | `string` | `"non_routable"` | no | Whether pod IPs are routable in the fabric: `non_routable` or `routable`. |
| `transit_gw_name` | `string` | `""` | aviatrix only | Aviatrix transit gateway name. Required when `transit_type = "aviatrix"`; must be empty otherwise. |
| `aws_tgw_id` | `string` | `""` | no | AWS Transit Gateway ID (e.g. `tgw-0abc...`). Optional when `transit_type = "aws_tgw"` (leave empty for standalone). Must be empty for other transit types. |
| `aws_cloudwan_core_network_arn` | `string` | `""` | no | AWS Cloud WAN Core Network ARN. Optional when `transit_type = "aws_cloudwan"` (standalone if empty). Must be empty for other transit types. |
| `east_west_cidrs` | `list(string)` | `["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]` | no | Destination CIDRs programmed on spoke route tables for east-west traffic (native modes only). |
| `additional_cluster_names` | `list(string)` | `[]` | no | Extra cluster names for `kubernetes.io/cluster/<name>=shared` subnet tags (multi-cluster-per-VPC). |
| `spoke_instance_size` | `string` | `"t3.medium"` | no | EC2 instance type for the Aviatrix spoke gateway. |
| `spoke_ha_gw` | `bool` | `false` | no | Deploy an HA spoke gateway. |
| `enable_vpc_dns_server` | `bool` | `true` | no | Use the VPC DNS server on the gateway (required for hostname SmartGroups and Route53 PHZ resolution). |
| `tags` | `map(string)` | `{}` | no | Additional tags applied to all resources. |

### Cross-field rules

The module enforces `transit_type`-to-target-variable consistency via an internal validation variable (`_validate_transit_inputs`; do not set it):

- `aviatrix`: `transit_gw_name` is **required** and non-empty; `aws_tgw_id` and `aws_cloudwan_core_network_arn` must be empty.
- `aws_tgw`: `transit_gw_name` must be empty; `aws_cloudwan_core_network_arn` must be empty; `aws_tgw_id` is optional.
- `aws_cloudwan`: `transit_gw_name` must be empty; `aws_tgw_id` must be empty; `aws_cloudwan_core_network_arn` is optional.

## SNAT behavior

### aviatrix mode

A dedicated `aviatrix_gateway_snat` resource is created with `snat_mode = "customized_snat"` and three policy classes:

| Policy | src_cidr | dst_cidr | interface | connection | Purpose |
|---|---|---|---|---|---|
| 1 | `var.pod_cidr` | `0.0.0.0/0` | (tunnel) | `var.transit_gw_name` | Pod east-west via Aviatrix transit — translate pod IP to spoke GW private IP before entering the fabric. |
| 2 | `var.pod_cidr` | `0.0.0.0/0` | `eth0` | — | Pod internet egress — translate pod IP to spoke GW private IP before sending to IGW. |
| 3 | each `infra_private` subnet CIDR | `0.0.0.0/0` | `eth0` | — | Node internet egress — translate node IP to spoke GW private IP (covers EKS node egress). |

### aws_tgw / aws_cloudwan mode

`single_ip_snat = true` is set on the mc-spoke module call. No `aviatrix_gateway_snat` resource is created. SNAT is performed by the Aviatrix gateway for all outbound traffic, masquerading as the gateway's private IP.

## Route-table programming (native modes)

Route entries are only programmed when `transit_type` is `aws_tgw` or `aws_cloudwan` AND the corresponding transit target ID/ARN is non-empty (`local.manage_native_routes = true`). With an empty target (standalone), the module programs nothing.

The spoke gateway's primary ENI (`data.aws_instance.spoke[0].network_interface_id`) is used as the next-hop for non-transit routes.

| Route table | Destination | Next hop | Condition |
|---|---|---|---|
| `avx_public` | Each CIDR in `east_west_cidrs` | TGW or Cloud WAN core network | aws_tgw or aws_cloudwan with target set |
| `infra_private` | `0.0.0.0/0` | Spoke gateway ENI | aws_tgw or aws_cloudwan with target set |
| `infra_private` | Each CIDR in `east_west_cidrs` | TGW or Cloud WAN core network | aws_tgw or aws_cloudwan with target set |
| `pod_private` | `0.0.0.0/0` | Spoke gateway ENI | aws_tgw or aws_cloudwan with target set |
| `pod_private` | Each CIDR in `east_west_cidrs` | Spoke gateway ENI | `pod_cidr_mode = "non_routable"` |
| `pod_private` | Each CIDR in `east_west_cidrs` | TGW or Cloud WAN core network | `pod_cidr_mode = "routable"` |

All route tables use `lifecycle { ignore_changes = [route] }` so Aviatrix controller-programmed RFC1918 routes (in aviatrix mode) are not removed on re-apply.

## Outputs

| Output | Description |
|---|---|
| `vpc_id` | VPC ID. |
| `vpc_cidr` | Primary VPC CIDR. |
| `pod_cidr` | Secondary VPC CIDR used for pod networking. |
| `secondary_cidr` | Alias of `pod_cidr` (for callers that prefer this name). |
| `availability_zones` | AZs used by this spoke (`[<region>a, <region>b]`). |
| `avx_gateway_subnet_ids` | Aviatrix gateway subnet IDs (one per AZ). |
| `avx_gateway_subnet_cidrs` | Aviatrix gateway subnet CIDR blocks (one per AZ). |
| `lb_public_subnet_ids` | Load-balancer public subnet IDs (one per AZ). |
| `lb_public_subnet_cidrs` | Load-balancer public subnet CIDR blocks. |
| `infra_private_subnet_ids` | Infrastructure private subnet IDs (EKS node subnets). |
| `infra_private_subnet_cidrs` | Infrastructure private subnet CIDR blocks. |
| `pod_private_subnet_ids` | Pod private subnet IDs (from secondary CIDR); consumed by ENIConfig in nodes layer. |
| `pod_private_subnet_cidrs` | Pod private subnet CIDR blocks. |
| `infra_private_route_table_id` | Infrastructure private route table ID. |
| `pod_private_route_table_id` | Pod private route table ID. |
| `spoke_gateway_name` | Aviatrix spoke gateway name. |
| `spoke_gateway_private_ip` | Aviatrix spoke gateway private IP (SNAT target for pod traffic). |
| `spoke_gateway` | Full spoke gateway object from mc-spoke (for advanced callers). |
| `spoke_vpc` | Spoke VPC object from mc-spoke. |

## Example: Aviatrix transit (full attach)

```hcl
module "spoke_vpc" {
  source = "../../modules/aws-eks-spoke-vpc"

  name                      = "frontend"
  cluster_name              = "frontend-cluster"
  region                    = "us-east-1"
  primary_cidr              = "10.1.0.0/23"
  pod_cidr                  = "100.64.0.0/16"
  aviatrix_aws_account_name = "my-aws-account"

  transit_type    = "aviatrix"
  transit_gw_name = "avx-transit-us-east-1"
}
```

## Example: AWS TGW (standalone, wired out-of-band)

```hcl
module "spoke_vpc" {
  source = "../../modules/aws-eks-spoke-vpc"

  name                      = "backend"
  cluster_name              = "backend-cluster"
  region                    = "us-west-2"
  primary_cidr              = "10.2.0.0/23"
  aviatrix_aws_account_name = "my-aws-account"

  transit_type = "aws_tgw"
  # aws_tgw_id intentionally omitted — attachment wired out-of-band.
  # Set aws_tgw_id = "tgw-0abc..." to have the module manage route entries.
}
```

## Example: AWS TGW (module manages routes)

```hcl
module "spoke_vpc" {
  source = "../../modules/aws-eks-spoke-vpc"

  name                      = "backend"
  cluster_name              = "backend-cluster"
  region                    = "us-west-2"
  primary_cidr              = "10.2.0.0/23"
  aviatrix_aws_account_name = "my-aws-account"

  transit_type = "aws_tgw"
  aws_tgw_id   = "tgw-0abc1234def56789"

  pod_cidr_mode   = "non_routable"
  east_west_cidrs = ["10.0.0.0/8"]
}
```

## Azure forward-looking note

A future `modules/azure-aks-spoke-vnet/` module would mirror this taxonomy with the following mapping:

| AWS concept | Azure equivalent |
|---|---|
| `aws_tgw_id` | `vnet_peer_id` + `next_hop_ip` |
| `aws_cloudwan_core_network_arn` | (Cloud WAN has no Azure equivalent; use `vnet_peer_id`) |
| `east_west_cidrs` + `aws_route` resources | UDR rules with the same destination set and next-hop IP |
| `transit_type` enum values | Same values; `aws_cloudwan` would be unused on Azure |
| `pod_cidr_mode` enum | Unchanged (`routable` / `non_routable`) |

AWS-specific variable names (`aws_tgw_id`, `aws_cloudwan_core_network_arn`) remain AWS-specific. The Azure module would introduce `vnet_peer_id` and `next_hop_ip` instead.

## Deferred / not yet implemented

- **`az_count`**: AZ count is hardcoded to 2. A future `az_count` variable would generalize to N AZs (subnet CIDR math and route-table associations are the affected surfaces).
- **`enable_public_lb_subnets`**: Public LB subnets are always created. A future toggle would make them optional for internal-only clusters.

## Requirements

| Tool | Version |
|---|---|
| Terraform | >= 1.9 |
| AWS provider | ~> 6.0 |
| Aviatrix provider | ~> 8.2.0 |
| mc-spoke module | ~> 8.2.0 |
