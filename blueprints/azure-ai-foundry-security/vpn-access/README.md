# VPN Access — Aviatrix P2S Gateway for Azure AI Foundry

Deploys an Aviatrix Point-to-Site (P2S) VPN gateway into the existing foundry VNet, giving individual developers and operators direct private access to the Azure AI Foundry deployment without requiring a transit gateway or hub network.

Use this module when there is no SD-WAN, ExpressRoute, or Aviatrix transit connection available and you need to reach Foundry services — AI Foundry hub, Azure OpenAI, Azure AI Search, CosmosDB, Storage — via their private endpoints from a local machine.

## Architecture

```
Your machine
    │
    │  OpenVPN (TLS)
    ▼
┌──────────────────────────────────────────────────────┐
│  Azure VNet  (10.11.0.0/23)  [foundry VNet]          │
│                                                      │
│  ┌──────────────────────────┐                        │
│  │  snet-avx-vpn-gw  /28   │                        │
│  │                          │                        │
│  │  ┌──────────────────┐   │                        │
│  │  │ Aviatrix VPN GW  │   │                        │
│  │  │  split tunnel    │   │                        │
│  │  │  VPN NAT (SNAT)  │   │                        │
│  │  └────────┬─────────┘   │                        │
│  └───────────┼─────────────┘                        │
│              │ routed to VNet CIDR only              │
│              ▼                                       │
│  ┌──────────────────────────────────────────────┐   │
│  │  snet-private-endpoint  /28                  │   │
│  │                                              │   │
│  │  Private Endpoints                           │   │
│  │  ├─ AI Foundry (Cognitive Services)          │   │
│  │  ├─ Azure OpenAI                             │   │
│  │  ├─ Azure Storage                            │   │
│  │  ├─ Azure CosmosDB                           │   │
│  │  └─ Azure AI Search                          │   │
│  └──────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
```

**Split tunnel**: only traffic destined to `foundry_vnet_cidr` (default `10.11.0.0/23`) is routed through the VPN. All other internet traffic exits locally as normal.

**VPN NAT**: the gateway SNATs the VPN client IP to its own private IP, so private endpoints see traffic originating from within the VNet and respond correctly.

**DNS**: private endpoint FQDNs (`*.privatelink.*.azure.com`) resolve to private IPs only within the VNet DNS context. Since the VPN client uses its local OS DNS, you must add the private endpoint mappings to your local hosts file — see [Connecting](#connecting).

## Prerequisites

- [Aviatrix Control Plane](../../docs/prerequisites/aviatrix-controller.md) (v8.2+) with the target Azure subscription onboarded as an access account
- [Terraform](../../docs/prerequisites/terraform.md) (v1.10+)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) — authenticated with `az login`
- `network-infra/` deployed — this module adds a subnet into the existing foundry VNet and requires its `resource_group_name` output

## Resources Created

| Resource | Description | Quantity |
|----------|-------------|----------|
| Azure Subnet | VPN gateway subnet (`snet-avx-vpn-gw`, `/28`) added to the existing foundry VNet | 1 |
| Aviatrix Gateway | P2S VPN gateway with split tunnel and NAT | 1 |
| Aviatrix VPN User | OVPN credential set for the specified user | 1 |

**Estimated Cost**: VPN gateway VM (Standard_B2ms) ~$0.05/hour while deployed.

## Deployment

### Step 1: Deploy network-infra first

The `vpn-access` module needs the foundry VNet to exist. If not yet deployed:

```bash
cd ../network-infra
terraform init && terraform apply
```

Note the `resource_group_name` output — you need it for `vnet_resource_group`.

### Step 2: Configure variables

```bash
cd ../vpn-access
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`. At minimum, set:
- `subscription_id`
- `vnet_resource_group` — from the `network-infra` `resource_group_name` output
- `vpn_user_name` and `vpn_user_email`
- Aviatrix controller credentials

If you changed `vnet_address_space` in `network-infra`, set `foundry_vnet_cidr` to the same value.

### Step 3: Deploy

```bash
terraform init
terraform plan
terraform apply
```

Deployment takes approximately 10–15 minutes (gateway creation is the slow step).

## Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `subscription_id` | Azure subscription ID | string | — | yes |
| `vnet_resource_group` | Resource group of the foundry VNet (network-infra output) | string | — | yes |
| `vpn_user_name` | VPN username | string | — | yes |
| `vpn_user_email` | VPN user email — OVPN profile sent here | string | — | yes |
| `avx_controller_ip` | Aviatrix controller FQDN or IP | string | — | yes |
| `avx_username` | Aviatrix controller admin username | string | — | yes |
| `avx_password` | Aviatrix controller admin password | string | — | yes |
| `avx_account_name` | Aviatrix access account name for the Azure subscription | string | — | yes |
| `location` | Azure region — must match foundry VNet region | string | `francecentral` | no |
| `vpc_reg` | Aviatrix region name (title-case, e.g. `France Central`) | string | `France Central` | no |
| `vnet_name` | Name of the existing foundry VNet | string | `vnet-foundry` | no |
| `foundry_vnet_cidr` | VNet CIDR routed through the VPN tunnel | string | `10.11.0.0/23` | no |
| `vpn_gw_subnet_cidr` | CIDR for the new VPN gateway subnet | string | `10.11.0.32/28` | no |
| `vpn_client_cidr` | IP pool assigned to VPN clients | string | `192.168.43.0/24` | no |
| `avx_vpn_gw_name` | VPN gateway base name (suffix appended) | string | `avx-vpn-foundry` | no |
| `avx_vpn_gw_size` | Azure VM size for the gateway | string | `Standard_B2ms` | no |

## Outputs

| Output | Description |
|--------|-------------|
| `vpn_gateway_name` | Aviatrix VPN gateway name |
| `vpn_gateway_public_ip` | Public IP of the VPN gateway |
| `vpn_user_name` | Created VPN username |

## Connecting

### Step 1: Download the OVPN profile

Two options:

**Option A — Email**: Aviatrix sends the `.ovpn` profile to `vpn_user_email` automatically after the user is created.

**Option B — CoPilot**: Open CoPilot → **CloudN** → **VPN** → **Users**, find the user, click **Download Profile**.

### Step 2: Import into your VPN client

The profile is standard OpenVPN. Import it into any OpenVPN-compatible client:

- **macOS / Windows**: [Tunnelblick](https://tunnelblick.net/) (macOS) or [OpenVPN Connect](https://openvpn.net/client/)
- **Linux**: `openvpn --config <profile>.ovpn`

Connect using the username and the password embedded in the profile (certificate-based — no separate password needed unless you configured one).

### Step 3: Add private endpoint entries to your hosts file

Private endpoint FQDNs resolve to private IPs only within the Azure private DNS zones. Your VPN client bypasses those zones. After connecting, add the entries from the `foundry-playground` deployment output to your local hosts file:

```bash
# In the foundry-playground directory, after terraform apply:
terraform output -raw hosts_file_entries
```

Copy the output and append it to:
- **macOS / Linux**: `/etc/hosts`
- **Windows**: `C:\Windows\System32\drivers\etc\hosts`

Example entries:
```
10.11.0.20 myaccount.blob.core.windows.net
10.11.0.21 mycosmosdb.documents.azure.com
10.11.0.22 myfoundrysearch.search.windows.net
10.11.0.23 aifoundryXXXX.cognitiveservices.azure.com
10.11.0.23 aifoundryXXXX.openai.azure.com
10.11.0.23 aifoundryXXXX.services.ai.azure.com
```

Once the hosts file is updated and the VPN is connected, traffic to those FQDNs routes through the tunnel to the private endpoints.

## Cleanup

```bash
terraform destroy
```

> **Note:** Gateway deletion takes 10–15 minutes — expected behavior, not a hang.

## Tested With

| Component | Version |
|-----------|---------|
| Aviatrix Controller | 8.2.x |
| Aviatrix Terraform Provider | 8.2.x |
| Terraform | 1.10.x |
| Azure Provider (azurerm) | 4.x |
| Random Provider | 3.x |
