output "resource_group_name" {
  description = "Resource group holding the demo storage account"
  value       = azurerm_resource_group.this.name
}

output "storage_account_id" {
  description = "Storage account resource ID; scope for RBAC assignments and private endpoints"
  value       = module.storage.id
}

output "storage_account_name" {
  description = "Storage account name"
  value       = module.storage.name
}

output "primary_blob_endpoint" {
  description = "Blob service endpoint for data-plane clients"
  value       = module.storage.primary_blob_endpoint
}
