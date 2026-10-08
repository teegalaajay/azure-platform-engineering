output "resource_group_name" {
  description = "Security resource group"
  value       = azurerm_resource_group.this.name
}

output "key_vault_id" {
  description = "Platform Key Vault resource ID; scope for role assignments in other roots"
  value       = azurerm_key_vault.this.id
}

output "key_vault_name" {
  description = "Platform Key Vault name"
  value       = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  description = "Data-plane endpoint (https://<name>.vault.azure.net/) for clients"
  value       = azurerm_key_vault.this.vault_uri
}
