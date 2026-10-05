output "vm_id" {
  description = "VM resource ID"
  value       = azurerm_linux_virtual_machine.this.id
}

output "nic_id" {
  description = "NIC resource ID"
  value       = azurerm_network_interface.this.id
}

output "private_ip_address" {
  description = "Private IP of the VM (the only address it has)"
  value       = azurerm_network_interface.this.private_ip_address
}
