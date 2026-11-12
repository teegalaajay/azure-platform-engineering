output "resource_group_name" {
  description = "Resource group holding the private DNS zones"
  value       = azurerm_resource_group.this.name
}

output "private_dns_zone_ids" {
  description = "Zone IDs keyed by short name (blob, vault, acr); private endpoint zone groups reference these"
  value       = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}

output "private_dns_zone_names" {
  description = "Zone names keyed by short name"
  value       = { for k, z in azurerm_private_dns_zone.this : k => z.name }
}
