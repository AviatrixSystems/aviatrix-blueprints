output "deployment_id" {
  description = "6-digit suffix appended to every named resource — identifies this deployment among multiple."
  value       = random_integer.deployment_id.result
}

output "spoke_gateway_name" {
  description = "Aviatrix spoke gateway name fronting the runner subnet."
  value       = aviatrix_spoke_gateway.runner.gw_name
  sensitive   = true
}

output "spoke_gateway_public_ip" {
  description = "Public IP of the Aviatrix spoke gateway — the SNAT egress address for all runner traffic. Feeds the test-egress workflow as the assertion target (also published to vars.GW_PUBLIC_IP_AWS)."
  value       = aviatrix_spoke_gateway.runner.public_ip
  sensitive   = true
}

output "runner_instance_id" {
  description = "EC2 instance ID of the runner VM."
  value       = aws_instance.runner.id
}

output "runner_instance_private_ip" {
  description = "Private IP of the runner EC2 instance inside the spoke VPC."
  value       = aws_instance.runner.private_ip
  sensitive   = true
}

output "runner_smart_group_uuid" {
  description = "UUID of the DCF SmartGroup matching the runner EC2."
  value       = aviatrix_smart_group.runner_vm.uuid
}
