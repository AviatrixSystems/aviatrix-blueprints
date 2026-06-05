output "deployment_id" {
  description = "6-digit suffix appended to every named resource — identifies this deployment among multiple."
  value       = random_integer.deployment_id.result
}

output "spoke_gateway_name" {
  description = "Aviatrix spoke gateway name fronting the runner subnet."
  value       = aviatrix_spoke_gateway.runner.gw_name
  sensitive   = true
}

output "runner_vm_private_ip" {
  description = "Private IP of the runner VM inside the spoke VNet."
  value       = azurerm_network_interface.runner.private_ip_address
  sensitive   = true
}

output "runner_smart_group_uuid" {
  description = "UUID of the DCF SmartGroup matching the runner VM."
  value       = aviatrix_smart_group.runner_vm.uuid
}

output "spoke_gateway_public_ip" {
  description = "Public IP of the Aviatrix spoke gateway — the SNAT egress address for all runner traffic. Feeds the test-egress workflow as the assertion target."
  value       = aviatrix_spoke_gateway.runner.public_ip
  sensitive   = true
}
