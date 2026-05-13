output "vm_private_ip" {
  description = "Private IP address of the VM"
  value       = azurerm_network_interface.vm.private_ip_address
}

output "vm_name" {
  description = "Name of the virtual machine"
  value       = azurerm_linux_virtual_machine.vm.name
}

output "vm_id" {
  description = "Azure resource ID of the VM"
  value       = azurerm_linux_virtual_machine.vm.id
}

output "private_key_pem" {
  description = "SSH private key for the VM (sensitive — for emergency access only)"
  value       = tls_private_key.vm.private_key_pem
  sensitive   = true
}
