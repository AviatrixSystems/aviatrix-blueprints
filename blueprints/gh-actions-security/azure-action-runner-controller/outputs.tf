output "deployment_id" {
  description = "6-digit suffix appended to every named resource."
  value       = random_integer.deployment_id.result
}

output "resource_group_name" {
  description = "Resource group hosting the spoke VNet and AKS cluster."
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "Spoke VNet ID."
  value       = azurerm_virtual_network.this.id
}

output "aks_subnet_id" {
  description = "AKS subnet ID."
  value       = azurerm_subnet.aks.id
}

output "spoke_gateway_name" {
  description = "Aviatrix spoke gateway name."
  value       = aviatrix_spoke_gateway.this.gw_name
  sensitive   = true
}

output "spoke_gateway_public_ip" {
  description = "Public IP of the spoke gateway — SNAT egress IP for AKS pods."
  value       = aviatrix_spoke_gateway.this.public_ip
  sensitive   = true
}

output "aks_cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "aks_kube_config" {
  description = "Raw kubeconfig (admin) for the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive   = true
}

output "aks_node_resource_group" {
  description = "AKS-managed node RG (where the underlying VMs/NICs live)."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "arc_runner_label" {
  description = "runs-on label to use in GitHub Actions workflows to target this ARC scale set."
  value       = var.arc_runner_name
}

output "runner_smart_group_uuid" {
  description = "UUID of the DCF SmartGroup matching runner pods."
  value       = aviatrix_smart_group.runner_pods.uuid
}
