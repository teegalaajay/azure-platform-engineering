output "resource_group_name" {
  description = "Hub network resource group"
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "Hub VNet ID (spoke roots peer to it)"
  value       = module.network.vnet_id
}

output "vnet_name" {
  description = "Hub VNet name"
  value       = module.network.vnet_name
}

output "mgmt_subnet_id" {
  description = "snet-mgmt ID (runner/agent placement, storage and Key Vault VNet rules)"
  value       = module.network.subnet_ids["mgmt"]
}
