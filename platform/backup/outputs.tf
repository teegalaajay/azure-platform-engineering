output "resource_group_name" {
  description = "Backup resource group"
  value       = azurerm_resource_group.this.name
}

output "vault_id" {
  description = "Backup vault resource ID; scope for protected-item and diagnostics references"
  value       = azurerm_recovery_services_vault.this.id
}

output "vault_name" {
  description = "Backup vault name; the protected-VM resource addresses the vault by name"
  value       = azurerm_recovery_services_vault.this.name
}

output "policy_ids" {
  description = "Backup policy IDs by tier (ADR-0045): standard daily, regulated every 4 hours"
  value = {
    standard  = azurerm_backup_policy_vm.standard.id
    regulated = azurerm_backup_policy_vm.regulated.id
  }
}
