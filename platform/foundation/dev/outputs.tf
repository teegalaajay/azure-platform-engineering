output "resource_group_name" {
  description = "Spoke network resource group"
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "Spoke VNet ID"
  value       = module.network.vnet_id
}

output "subnet_ids" {
  description = "Spoke subnet IDs keyed by app/data (workloads attach here)"
  value       = module.network.subnet_ids
}
