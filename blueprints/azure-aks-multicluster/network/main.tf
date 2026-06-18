terraform {
  required_version = ">= 1.5"

  required_providers {
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "~> 8.2"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aviatrix" {
  controller_ip           = var.aviatrix_controller_ip
  username                = var.aviatrix_username
  password                = var.aviatrix_password
  skip_version_validation = true
}

provider "azurerm" {
  features {}
}

locals {
  clusters = {
    frontend = {
      name      = "${var.name_prefix}-frontend"
      vnet_cidr = var.frontend_vnet_cidr
    }
    backend = {
      name      = "${var.name_prefix}-backend"
      vnet_cidr = var.backend_vnet_cidr
    }
  }

  common_tags = {
    Environment = "demo"
    Terraform   = "true"
    Blueprint   = "azure-aks-multicluster"
  }

  # Static private IPs for NGINX internal LBs — referenced by AppGW backend pools
  # and consumed by nodes layer via remote_state outputs.
  # Must be within system subnet (x.0.128/25), away from AppGW subnet (x.0.64/26).
  frontend_nginx_lb_ip = "10.10.0.200"
  backend_nginx_lb_ip  = "10.20.0.200"
}

#####################
# Aviatrix Transit Gateway
#####################

module "azure_transit" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "~> 8.0"

  name    = "${var.name_prefix}-transit"
  cloud   = "Azure"
  account = var.aviatrix_azure_account_name
  region  = var.aviatrix_azure_region
  cidr    = var.transit_cidr
  ha_gw   = false

  # FireNet is intentionally disabled — this blueprint does not deploy NGFWs.
  # Enabling FireNet requires a 3-NIC VM size (e.g., Standard_B2ms) and adds
  # provisioning complexity. To add NGFWs later, set enable_transit_firenet = true
  # AND change instance_size to a 3+ NIC SKU (B2ms, DS3_v2, F4s_v2, D8s_v5).

  # D-series has more reliable zonal capacity in eastus2 than B-series.
  # Same vCPU/RAM (2/8 GB) as B2ms, ~$0.013/hr more per gateway.
  instance_size     = "Standard_D2s_v3"
  connected_transit = true

  # NOTE: enable_vpc_dns_server is intentionally OFF.
  # The post-deploy DNS check fails consistently against this controller (9.0.10).
  # Hostname-based SmartGroups for *private* FQDNs (Azure Private DNS) won't
  # resolve via the GW; VNet-based SmartGroups still work and cover east-west.

  # CRITICAL: Exclude the pod CIDR from BGP advertisements.
  # Both clusters share 100.64.0.0/16 as their Cilium overlay — the spoke GWs
  # SNAT pod traffic to their own private IP via aviatrix_gateway_snat
  # (customized_snat) before forwarding to transit, so the transit must never
  # advertise the raw pod CIDR to peers.
  excluded_advertised_spoke_routes = var.pod_cidr
}

#####################
# Frontend VNet + Spoke Gateway
#####################

module "frontend_vnet" {
  source = "./modules/aks-vnet"

  name         = "frontend"
  cluster_name = local.clusters.frontend.name
  vnet_cidr    = local.clusters.frontend.vnet_cidr
  pod_cidr     = var.pod_cidr
  region       = var.azure_region
  name_prefix  = var.name_prefix
  tags         = merge(local.common_tags, { Cluster = "frontend" })
}

# UDR: route all egress from AKS nodes through the Aviatrix spoke gateway.
# This MUST be associated with the nodes subnet before the AKS cluster is created
# (outbound_type = "userDefinedRouting" requires it to exist at cluster creation time).
resource "azurerm_route_table" "frontend_udr" {
  name                          = "${var.name_prefix}-frontend-udr"
  location                      = var.azure_region
  resource_group_name           = module.frontend_vnet.resource_group_name
  bgp_route_propagation_enabled = false
  tags                          = merge(local.common_tags, { Cluster = "frontend" })
}

resource "azurerm_subnet_route_table_association" "frontend_nodes_udr" {
  subnet_id      = module.frontend_vnet.nodes_subnet_id
  route_table_id = azurerm_route_table.frontend_udr.id
}

# Aviatrix requires ALL private subnets in the VNet to have a route table
resource "azurerm_subnet_route_table_association" "frontend_system_udr" {
  subnet_id      = module.frontend_vnet.system_subnet_id
  route_table_id = azurerm_route_table.frontend_udr.id
}

# Pod subnet UDR — pods egress through the spoke GW, where DCF inspects pod-source
# IPs and customized_snat fires. Without this UDR, pod traffic wouldn't reach the
# Aviatrix gateway and DCF inspection would never trigger.
resource "azurerm_subnet_route_table_association" "frontend_pods_udr" {
  subnet_id      = module.frontend_vnet.pod_subnet_id
  route_table_id = azurerm_route_table.frontend_udr.id
}

# Default route required by AKS `outbound_type = userDefinedRouting`.
# Aviatrix auto-programs RFC1918 routes (10/8, 172.16/12, 192.168/16) on the
# UDR but not 0.0.0.0/0, because transit doesn't advertise a default route
# without an internet-facing egress device. Spoke GW handles internet egress
# via SNAT on its own public IP.
resource "azurerm_route" "frontend_default" {
  name                   = "default-via-spoke-gw"
  resource_group_name    = module.frontend_vnet.resource_group_name
  route_table_name       = azurerm_route_table.frontend_udr.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = nonsensitive(module.frontend_spoke.spoke_gateway.private_ip)
}

module "frontend_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  cloud      = "Azure"
  name       = "${var.name_prefix}-frontend-spoke"
  account    = var.aviatrix_azure_account_name
  region     = var.aviatrix_azure_region
  transit_gw = module.azure_transit.transit_gateway.gw_name

  # D-series has more reliable zonal capacity in eastus2 than B-series
  # (B2ms hits ZonalAllocationFailed in some zones). Same vCPU/RAM (2/8 GB),
  # ~$0.013/hr more per gateway.
  instance_size = "Standard_D2s_v3"
  ha_gw         = false

  # See comment in transit module above — DNS check fails on this controller.

  # Pods egress with their original 100.64.x.x source IPs so DCF inspects pod
  # IPs at this gateway. The aviatrix_gateway_snat resource below SNATs pod
  # CIDR + VNet CIDR to the spoke GW's private IP per direction (transit
  # connection + eth0) so the destination cluster's identical pod CIDR doesn't
  # collide on reply, and AKS nodes still get internet egress for CSE bootstrap.
  single_ip_snat = false

  # Deploy spoke GW into the VNet created by aks-vnet module
  use_existing_vpc = true
  vpc_id           = module.frontend_vnet.aviatrix_vpc_id # "vnet_name:rg_name"
  gw_subnet        = module.frontend_vnet.avx_gateway_subnet_cidr

  depends_on = [
    azurerm_subnet_route_table_association.frontend_nodes_udr,
    azurerm_subnet_route_table_association.frontend_system_udr,
  ]
}

# CRITICAL: Custom SNAT for pod traffic (100.64.0.0/16) and VNet traffic.
# Pod CIDR is SNATed to the spoke GW IP per direction so overlapping pod
# CIDRs across clusters don't collide on the IPsec reply path. VNet CIDR is
# SNATed for eth0 so AKS nodes (10.10.0.x) can egress to the internet (CSE
# image pulls, kubelet → Azure ARM, etc.) — without this they'd leave the GW
# with an unroutable RFC1918 source.
resource "aviatrix_gateway_snat" "frontend" {
  gw_name   = module.frontend_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  # Pod CIDR — east-west via transit IPsec connection
  snat_policy {
    src_cidr   = var.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.azure_transit.transit_gateway.gw_name
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  # Pod CIDR — internet egress via eth0
  snat_policy {
    src_cidr   = var.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  # Frontend VNet (covers AKS nodes + system subnet) — east-west via transit
  snat_policy {
    src_cidr   = var.frontend_vnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.azure_transit.transit_gateway.gw_name
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  # Frontend VNet — internet egress via eth0 (required for AKS node CSE bootstrap)
  snat_policy {
    src_cidr   = var.frontend_vnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.frontend_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.frontend_spoke]
}

#####################
# Backend VNet + Spoke Gateway
#####################

module "backend_vnet" {
  source = "./modules/aks-vnet"

  name         = "backend"
  cluster_name = local.clusters.backend.name
  vnet_cidr    = local.clusters.backend.vnet_cidr
  pod_cidr     = var.pod_cidr
  region       = var.azure_region
  name_prefix  = var.name_prefix
  tags         = merge(local.common_tags, { Cluster = "backend" })
}

resource "azurerm_route_table" "backend_udr" {
  name                          = "${var.name_prefix}-backend-udr"
  location                      = var.azure_region
  resource_group_name           = module.backend_vnet.resource_group_name
  bgp_route_propagation_enabled = false
  tags                          = merge(local.common_tags, { Cluster = "backend" })
}

resource "azurerm_subnet_route_table_association" "backend_nodes_udr" {
  subnet_id      = module.backend_vnet.nodes_subnet_id
  route_table_id = azurerm_route_table.backend_udr.id
}

resource "azurerm_subnet_route_table_association" "backend_system_udr" {
  subnet_id      = module.backend_vnet.system_subnet_id
  route_table_id = azurerm_route_table.backend_udr.id
}

resource "azurerm_subnet_route_table_association" "backend_pods_udr" {
  subnet_id      = module.backend_vnet.pod_subnet_id
  route_table_id = azurerm_route_table.backend_udr.id
}

# See comment on frontend_default for rationale.
resource "azurerm_route" "backend_default" {
  name                   = "default-via-spoke-gw"
  resource_group_name    = module.backend_vnet.resource_group_name
  route_table_name       = azurerm_route_table.backend_udr.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = nonsensitive(module.backend_spoke.spoke_gateway.private_ip)
}

module "backend_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  cloud      = "Azure"
  name       = "${var.name_prefix}-backend-spoke"
  account    = var.aviatrix_azure_account_name
  region     = var.aviatrix_azure_region
  transit_gw = module.azure_transit.transit_gateway.gw_name

  # D-series has more reliable zonal capacity in eastus2 than B-series
  # (B2ms hits ZonalAllocationFailed in some zones). Same vCPU/RAM (2/8 GB),
  # ~$0.013/hr more per gateway.
  instance_size = "Standard_D2s_v3"
  ha_gw         = false

  # See comment in transit module above — DNS check fails on this controller.

  # See comment on frontend_spoke single_ip_snat — pods preserve original IPs
  # so DCF inspects pod source. aviatrix_gateway_snat below handles SNAT.
  single_ip_snat = false

  use_existing_vpc = true
  vpc_id           = module.backend_vnet.aviatrix_vpc_id
  gw_subnet        = module.backend_vnet.avx_gateway_subnet_cidr

  depends_on = [
    azurerm_subnet_route_table_association.backend_nodes_udr,
    azurerm_subnet_route_table_association.backend_system_udr,
  ]
}

resource "aviatrix_gateway_snat" "backend" {
  gw_name   = module.backend_spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  snat_policy {
    src_cidr   = var.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.azure_transit.transit_gateway.gw_name
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = var.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = var.backend_vnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = module.azure_transit.transit_gateway.gw_name
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = var.backend_vnet_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.backend_spoke.spoke_gateway.private_ip
  }

  depends_on = [module.backend_spoke]
}

#####################
# DB Spoke (test VM for east-west traffic demo)
#####################

resource "azurerm_resource_group" "db" {
  name     = "${var.name_prefix}-db-rg"
  location = var.azure_region
  tags     = merge(local.common_tags, { Role = "db" })
}

resource "azurerm_virtual_network" "db" {
  name                = "${var.name_prefix}-db-vnet"
  location            = azurerm_resource_group.db.location
  resource_group_name = azurerm_resource_group.db.name
  address_space       = [var.db_vnet_cidr]
  tags                = merge(local.common_tags, { Role = "db" })
}

resource "azurerm_subnet" "db_avx_gw" {
  name                 = "db-avx-gw"
  resource_group_name  = azurerm_resource_group.db.name
  virtual_network_name = azurerm_virtual_network.db.name
  address_prefixes     = [cidrsubnet(var.db_vnet_cidr, 6, 0)] # /28
}

resource "azurerm_subnet" "db_vms" {
  name                 = "db-vms"
  resource_group_name  = azurerm_resource_group.db.name
  virtual_network_name = azurerm_virtual_network.db.name
  address_prefixes     = [cidrsubnet(var.db_vnet_cidr, 2, 1)] # /24
}

# Aviatrix requires a route table associated with private subnets before deploying
# the spoke gateway into an existing VNet ([AVXERR-TRANSIT-0067]).
resource "azurerm_route_table" "db_udr" {
  name                          = "${var.name_prefix}-db-udr"
  location                      = var.azure_region
  resource_group_name           = azurerm_resource_group.db.name
  bgp_route_propagation_enabled = false
  tags                          = merge(local.common_tags, { Role = "db" })
}

resource "azurerm_subnet_route_table_association" "db_vms_udr" {
  subnet_id      = azurerm_subnet.db_vms.id
  route_table_id = azurerm_route_table.db_udr.id
}

module "db_spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.0"

  cloud      = "Azure"
  name       = "${var.name_prefix}-db-spoke"
  account    = var.aviatrix_azure_account_name
  region     = var.aviatrix_azure_region
  transit_gw = module.azure_transit.transit_gateway.gw_name

  instance_size  = "Standard_D2s_v3"
  ha_gw          = false
  single_ip_snat = true

  # See comment in transit module above — DNS check fails on this controller.

  use_existing_vpc = true
  vpc_id           = "${azurerm_virtual_network.db.name}:${azurerm_resource_group.db.name}"
  gw_subnet        = azurerm_subnet.db_avx_gw.address_prefixes[0]

  depends_on = [azurerm_subnet_route_table_association.db_vms_udr]
}

module "db_vm" {
  source = "./modules/linux-vm"

  name_prefix         = var.name_prefix
  resource_group_name = azurerm_resource_group.db.name
  location            = var.azure_region
  subnet_id           = azurerm_subnet.db_vms.id
  tags                = merge(local.common_tags, { Role = "db-test-vm" })

  depends_on = [module.db_spoke]
}

#####################
# Application Gateway Subnets
# CRITICAL: Do NOT associate the Aviatrix UDR with these subnets.
# AppGW management traffic (GatewayManager → ports 65200-65535) must reach
# the Azure platform directly. A 0.0.0.0/0 → VirtualAppliance route breaks AppGW.
#####################

resource "azurerm_subnet" "frontend_appgw" {
  name                 = "frontend-appgw"
  resource_group_name  = module.frontend_vnet.resource_group_name
  virtual_network_name = module.frontend_vnet.vnet_name
  address_prefixes     = [cidrsubnet(var.frontend_vnet_cidr, 3, 1)] # 10.10.0.64/26
}

resource "azurerm_subnet" "backend_appgw" {
  name                 = "backend-appgw"
  resource_group_name  = module.backend_vnet.resource_group_name
  virtual_network_name = module.backend_vnet.vnet_name
  address_prefixes     = [cidrsubnet(var.backend_vnet_cidr, 3, 1)] # 10.20.0.64/26
}

#####################
# Application Gateway Public IPs
#####################

resource "azurerm_public_ip" "frontend_appgw" {
  name                = "${var.name_prefix}-frontend-appgw-pip"
  location            = var.azure_region
  resource_group_name = module.frontend_vnet.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = merge(local.common_tags, { Cluster = "frontend" })
}

resource "azurerm_public_ip" "backend_appgw" {
  name                = "${var.name_prefix}-backend-appgw-pip"
  location            = var.azure_region
  resource_group_name = module.backend_vnet.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = merge(local.common_tags, { Cluster = "backend" })
}

#####################
# Azure Application Gateways (Standard_v2)
# Traffic path: Internet → AppGW PIP:80 → NGINX internal LB (10.x.0.200):80 → Gatus pods:8080
# AppGW terminates the TCP connection — response traffic is VNet-internal, avoiding
# asymmetric routing through the Aviatrix UDR.
#####################

resource "azurerm_application_gateway" "frontend" {
  name                = "${var.name_prefix}-frontend-appgw"
  location            = var.azure_region
  resource_group_name = module.frontend_vnet.resource_group_name
  tags                = merge(local.common_tags, { Cluster = "frontend" })

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "appgw-ipconfig"
    subnet_id = azurerm_subnet.frontend_appgw.id
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "appgw-fip"
    public_ip_address_id = azurerm_public_ip.frontend_appgw.id
  }

  backend_address_pool {
    name         = "nginx-pool"
    ip_addresses = [local.frontend_nginx_lb_ip]
  }

  probe {
    name                = "nginx-health"
    protocol            = "Http"
    host                = "health.local"
    path                = "/health"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    port                = 80
    match {
      status_code = ["200-399"]
    }
  }

  backend_http_settings {
    name                  = "nginx-http"
    cookie_based_affinity = "Disabled"
    protocol              = "Http"
    port                  = 80
    request_timeout       = 30
    probe_name            = "nginx-health"
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "appgw-fip"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "http-rule"
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "nginx-pool"
    backend_http_settings_name = "nginx-http"
  }
}

resource "azurerm_application_gateway" "backend" {
  name                = "${var.name_prefix}-backend-appgw"
  location            = var.azure_region
  resource_group_name = module.backend_vnet.resource_group_name
  tags                = merge(local.common_tags, { Cluster = "backend" })

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "appgw-ipconfig"
    subnet_id = azurerm_subnet.backend_appgw.id
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "appgw-fip"
    public_ip_address_id = azurerm_public_ip.backend_appgw.id
  }

  backend_address_pool {
    name         = "nginx-pool"
    ip_addresses = [local.backend_nginx_lb_ip]
  }

  probe {
    name                = "nginx-health"
    protocol            = "Http"
    host                = "health.local"
    path                = "/health"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    port                = 80
    match {
      status_code = ["200-399"]
    }
  }

  backend_http_settings {
    name                  = "nginx-http"
    cookie_based_affinity = "Disabled"
    protocol              = "Http"
    port                  = 80
    request_timeout       = 30
    probe_name            = "nginx-health"
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "appgw-fip"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "http-rule"
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "nginx-pool"
    backend_http_settings_name = "nginx-http"
  }
}

#####################
# Shared Services: Private DNS Zone
#####################

resource "azurerm_resource_group" "shared" {
  name     = "${var.name_prefix}-shared-rg"
  location = var.azure_region
  tags     = merge(local.common_tags, { Role = "shared" })
}

resource "azurerm_private_dns_zone" "main" {
  name                = var.private_dns_zone_name
  resource_group_name = azurerm_resource_group.shared.name
  tags                = merge(local.common_tags, { Role = "dns" })
}

# Link private DNS zone to all VNets so pods can resolve service DNS names
resource "azurerm_private_dns_zone_virtual_network_link" "frontend" {
  name                  = "${var.name_prefix}-frontend-dns-link"
  resource_group_name   = azurerm_resource_group.shared.name
  private_dns_zone_name = azurerm_private_dns_zone.main.name
  virtual_network_id    = module.frontend_vnet.vnet_id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "backend" {
  name                  = "${var.name_prefix}-backend-dns-link"
  resource_group_name   = azurerm_resource_group.shared.name
  private_dns_zone_name = azurerm_private_dns_zone.main.name
  virtual_network_id    = module.backend_vnet.vnet_id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "db" {
  name                  = "${var.name_prefix}-db-dns-link"
  resource_group_name   = azurerm_resource_group.shared.name
  private_dns_zone_name = azurerm_private_dns_zone.main.name
  virtual_network_id    = azurerm_virtual_network.db.id
  registration_enabled  = false
  tags                  = local.common_tags
}

# Static DNS record for the DB VM
resource "azurerm_private_dns_a_record" "db" {
  name                = "db"
  zone_name           = azurerm_private_dns_zone.main.name
  resource_group_name = azurerm_resource_group.shared.name
  ttl                 = 300
  records             = [module.db_vm.vm_private_ip]
}
