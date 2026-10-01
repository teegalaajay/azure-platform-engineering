output "id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Storage account name"
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Blob service endpoint"
  value       = azurerm_storage_account.this.primary_blob_endpoint
}
