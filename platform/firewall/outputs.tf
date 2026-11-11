output "resource_group_name" {
  description = "Resource group of the firewall root"
  value       = azurerm_resource_group.this.name
}

output "firewall_private_ip" {
  description = "Next hop of the dev snet-app routes"
  value       = azurerm_firewall.this.ip_configuration[0].private_ip_address
}

output "firewall_public_ip" {
  description = "SNAT address: what an outside service sees for traffic leaving through the firewall"
  value       = azurerm_public_ip.firewall.ip_address
}

output "route_table_id" {
  description = "Route table associated with dev snet-app"
  value       = azurerm_route_table.dev_app.id
}
