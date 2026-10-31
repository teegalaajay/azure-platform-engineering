output "resource_group_name" {
  description = "Resource group created by the pipeline demo"
  value       = azurerm_resource_group.this.name
}

output "resource_group_id" {
  description = "Resource group ID; scope for later role assignments"
  value       = azurerm_resource_group.this.id
}
