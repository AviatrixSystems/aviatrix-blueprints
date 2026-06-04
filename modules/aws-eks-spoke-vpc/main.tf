locals {
  az_names = [
    "${var.region}a",
    "${var.region}b",
  ]

  default_tags = merge(var.tags, {
    Name = var.name
  })

  is_aviatrix          = var.transit_type == "aviatrix"
  is_native            = var.transit_type == "aws_tgw" || var.transit_type == "aws_cloudwan"
  native_target        = var.transit_type == "aws_tgw" ? var.aws_tgw_id : var.aws_cloudwan_core_network_arn
  manage_native_routes = local.is_native && local.native_target != ""

  # Cluster names to tag subnets with for EKS auto-discovery.
  cluster_names = distinct(concat([var.cluster_name], var.additional_cluster_names))
}

#####################
# VPC + secondary CIDR for pods
#####################

resource "aws_vpc" "this" {
  cidr_block           = var.primary_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.default_tags
}

resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  vpc_id     = aws_vpc.this.id
  cidr_block = var.pod_cidr
}

#####################
# Internet gateway + route tables
#
# RFC1918 routes on the private RT are programmed by the Aviatrix spoke
# gateway after attach. ignore_changes prevents Terraform from removing
# them on every plan.
#####################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}

resource "aws_route_table" "avx_public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-avx-public-rt"
    Type = "aviatrix-gateway"
  })

  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table" "lb_public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-lb-public-rt"
    Type = "load-balancer"
  })

  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table" "infra_private" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-infra-private-rt"
    Type = "infrastructure"
  })

  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table" "pod_private" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-pod-private-rt"
    Type = "pod"
  })

  lifecycle {
    ignore_changes = [route]
  }
}

#####################
# Aviatrix gateway subnets (/28)
#####################

resource "aws_subnet" "avx_public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.primary_cidr, 5, count.index)
  availability_zone       = local.az_names[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name}-avx-public-${local.az_names[count.index]}"
    Type = "aviatrix-gateway"
  })
}

resource "aws_route_table_association" "avx_public" {
  count          = 2
  subnet_id      = aws_subnet.avx_public[count.index].id
  route_table_id = aws_route_table.avx_public.id
}

#####################
# Load-balancer subnets (/26, public, ELB-tagged)
#####################

resource "aws_subnet" "lb_public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.primary_cidr, 3, count.index + 1)
  availability_zone       = local.az_names[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      Name                     = "${var.name}-lb-public-${local.az_names[count.index]}"
      Type                     = "load-balancer"
      "kubernetes.io/role/elb" = "1"
    },
    { for n in local.cluster_names : "kubernetes.io/cluster/${n}" => "shared" }
  )
}

resource "aws_route_table_association" "lb_public" {
  count          = 2
  subnet_id      = aws_subnet.lb_public[count.index].id
  route_table_id = aws_route_table.lb_public.id
}

#####################
# Infrastructure subnets (/26, private, EKS node + internal-elb tagged)
#####################

resource "aws_subnet" "infra_private" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.primary_cidr, 3, count.index + 5)
  availability_zone = local.az_names[count.index]

  tags = merge(
    var.tags,
    {
      Name                              = "${var.name}-infra-private-${local.az_names[count.index]}"
      Type                              = "infrastructure"
      "kubernetes.io/role/internal-elb" = "1"
    },
    { for n in local.cluster_names : "kubernetes.io/cluster/${n}" => "shared" }
  )
}

resource "aws_route_table_association" "infra_private" {
  count          = 2
  subnet_id      = aws_subnet.infra_private[count.index].id
  route_table_id = aws_route_table.infra_private.id
}

#####################
# Pod subnets (/17, from secondary CIDR -- can overlap across spokes)
#####################

resource "aws_subnet" "pod_private" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.pod_cidr, 1, count.index)
  availability_zone = local.az_names[count.index]

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-pod-private-${local.az_names[count.index]}"
      Type = "pod"
    },
    { for n in local.cluster_names : "kubernetes.io/cluster/${n}" => "shared" }
  )

  depends_on = [aws_vpc_ipv4_cidr_block_association.secondary]
}

resource "aws_route_table_association" "pod_private" {
  count          = 2
  subnet_id      = aws_subnet.pod_private[count.index].id
  route_table_id = aws_route_table.pod_private.id
}

#####################
# Aviatrix spoke gateway
#####################

module "spoke" {
  source  = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version = "~> 8.2.0"

  cloud      = "AWS"
  name       = "${var.name}-spoke"
  account    = var.aviatrix_aws_account_name
  region     = var.region
  transit_gw = var.transit_gw_name

  instance_size = var.spoke_instance_size
  ha_gw         = var.spoke_ha_gw

  enable_vpc_dns_server = var.enable_vpc_dns_server

  use_existing_vpc = true
  vpc_id           = aws_vpc.this.id
  gw_subnet        = aws_subnet.avx_public[0].cidr_block
  hagw_subnet      = aws_subnet.avx_public[1].cidr_block

  skip_public_route_table_update = false
}

#####################
# Custom SNAT for pod traffic
#
# Pods use a non-routable secondary CIDR (e.g. 100.64.0.0/16) that may
# overlap with other spokes. Aviatrix SNAT translates pod source IPs to
# the spoke gateway private IP before traffic enters transit -- this is
# what lets multiple spokes share an overlay CIDR.
#
# Three policy classes:
#   1. Pod CIDR -> any destination via transit GW connection
#   2. Pod CIDR -> internet via eth0
#   3. Each infra subnet -> internet via eth0 (for EKS node egress)
#####################

resource "aviatrix_gateway_snat" "this" {
  gw_name   = module.spoke.spoke_gateway.gw_name
  snat_mode = "customized_snat"

  snat_policy {
    src_cidr   = var.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = ""
    connection = var.transit_gw_name
    snat_ips   = module.spoke.spoke_gateway.private_ip
  }

  snat_policy {
    src_cidr   = var.pod_cidr
    dst_cidr   = "0.0.0.0/0"
    protocol   = "all"
    interface  = "eth0"
    connection = ""
    snat_ips   = module.spoke.spoke_gateway.private_ip
  }

  dynamic "snat_policy" {
    for_each = aws_subnet.infra_private[*].cidr_block
    content {
      src_cidr   = snat_policy.value
      dst_cidr   = "0.0.0.0/0"
      protocol   = "all"
      interface  = "eth0"
      connection = ""
      snat_ips   = module.spoke.spoke_gateway.private_ip
    }
  }

  depends_on = [module.spoke]
}
