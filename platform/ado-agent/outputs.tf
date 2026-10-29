output "resource_group_name" {
  description = "Resource group holding the agent VM and its NAT Gateway"
  value       = azurerm_resource_group.this.name
}

output "vm_id" {
  description = "Resource ID of the agent VM"
  value       = module.agent.vm_id
}

output "private_ip_address" {
  description = "Private IP of the agent VM in snet-mgmt (the only address the VM has)"
  value       = module.agent.private_ip_address
}

output "nat_egress_ip" {
  description = "Public IP the agent's outbound traffic leaves from (interim NAT Gateway, ADR-0007)"
  value       = azurerm_public_ip.nat.ip_address
}
