output "vpc_id" { value = module.spoke_vpc.vpc_id }
output "vpc_cidr" { value = module.spoke_vpc.vpc_cidr }
output "secondary_cidr" { value = module.spoke_vpc.secondary_cidr }
output "availability_zones" { value = module.spoke_vpc.availability_zones }
output "cluster_name" { value = local.cluster_name }

output "lb_public_subnet_ids" { value = module.spoke_vpc.lb_public_subnet_ids }
output "infra_private_subnet_ids" { value = module.spoke_vpc.infra_private_subnet_ids }
output "infra_private_subnet_cidrs" { value = module.spoke_vpc.infra_private_subnet_cidrs }
output "pod_private_subnet_ids" { value = module.spoke_vpc.pod_private_subnet_ids }

output "spoke_gateway_name" { value = module.spoke_vpc.spoke_gateway_name }
output "spoke_gateway_private_ip" { value = module.spoke_vpc.spoke_gateway_private_ip }
