output "resource_group_name" {
  description = "Resource group holding the shared private endpoints"
  value       = azurerm_resource_group.this.name
}

output "private_endpoint_names" {
  description = "Private endpoint names, keyed by service (vault, state_blob)"
  value       = { for k, v in azurerm_private_endpoint.this : k => v.name }
}

output "private_ip_addresses" {
  description = "Private IP address of each endpoint, keyed by service (vault, state_blob)"
  value       = { for k, v in azurerm_private_endpoint.this : k => v.private_service_connection[0].private_ip_address }
}
