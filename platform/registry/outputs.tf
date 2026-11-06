output "resource_group_name" {
  description = "Registry resource group"
  value       = azurerm_resource_group.this.name
}

output "registry_id" {
  description = "Registry resource ID; scope for AcrPull assignments in consumer roots (ADR-0036)"
  value       = azurerm_container_registry.this.id
}

output "registry_name" {
  description = "Registry name"
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "Registry host name (<name>.azurecr.io) used in image references"
  value       = azurerm_container_registry.this.login_server
}
