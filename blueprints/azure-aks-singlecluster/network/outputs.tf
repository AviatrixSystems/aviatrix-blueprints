output "name_prefix" {
  value = var.name_prefix
}

output "azure_region" {
  value = var.azure_region
}

output "resource_group_name" {
  value = module.spoke_vnet.resource_group_name
}

output "vnet_id" {
  value = module.spoke_vnet.vnet_id
}

output "cluster_name" {
  value = local.cluster_name
}

output "node_subnet_id" {
  value = module.spoke_vnet.node_subnet_id
}

output "pod_subnet_id" {
  value = module.spoke_vnet.pod_subnet_id
}

output "ingress_subnet_id" {
  value = module.spoke_vnet.ingress_subnet_id
}

output "ingress_subnet_name" {
  value = module.spoke_vnet.ingress_subnet_name
}

output "node_route_table_id" {
  value = module.spoke_vnet.node_route_table_id
}

output "pod_route_table_id" {
  value = module.spoke_vnet.pod_route_table_id
}

output "spoke_gateway_name" {
  value = module.spoke_vnet.spoke_gateway_name
}

output "spoke_gateway_public_ip" {
  value = module.spoke_vnet.spoke_gateway_public_ip
}

output "service_cidr" {
  value = var.service_cidr
}

output "dns_service_ip" {
  value = var.dns_service_ip
}

output "dcf_ruleset_uuid" {
  value = aviatrix_dcf_ruleset.egress.id
}

output "smartgroup_cluster_vpc_uuid" {
  value = aviatrix_smart_group.cluster_vpc.uuid
}
