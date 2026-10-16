output "resource_group_name" {
  description = "Runner resource group"
  value       = azurerm_resource_group.this.name
}

output "vm_id" {
  description = "Runner VM resource ID"
  value       = module.runner.vm_id
}

output "private_ip_address" {
  description = "Runner private IP (its only address)"
  value       = module.runner.private_ip_address
}

output "nat_public_ip" {
  description = "Egress address of snet-mgmt while the NAT Gateway exists (egress proof)"
  value       = azurerm_public_ip.nat.ip_address
}
