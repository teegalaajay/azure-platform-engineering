output "resource_group_name" {
  description = "Management resource group"
  value       = azurerm_resource_group.this.name
}

output "workspace_id" {
  description = "Log Analytics workspace resource ID; destination for diagnostic settings in policy and other roots"
  value       = azurerm_log_analytics_workspace.this.id
}

output "workspace_name" {
  description = "Log Analytics workspace name"
  value       = azurerm_log_analytics_workspace.this.name
}
