output "vnet_id" {
  description = "VNet resource ID (used for peering)"
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "VNet name"
  value       = azurerm_virtual_network.this.name
}

output "subnet_ids" {
  description = "Subnet IDs keyed like var.subnets, e.g. subnet_ids[\"app\"]"
  value       = { for k, s in azurerm_subnet.this : k => s.id }
}

output "nsg_ids" {
  description = "NSG IDs keyed like var.subnets"
  value       = { for k, n in azurerm_network_security_group.this : k => n.id }
}
