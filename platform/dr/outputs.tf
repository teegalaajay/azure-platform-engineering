output "resource_group_name" {
  description = "Resource group holding the ASR vault and DR networks."
  value       = azurerm_resource_group.this.name
}

output "resource_group_id" {
  description = "ID of the DR resource group; the target resource group for replica disks and failed-over VMs."
  value       = azurerm_resource_group.this.id
}

output "vault_name" {
  description = "ASR vault name."
  value       = azurerm_recovery_services_vault.this.name
}

output "source_fabric_name" {
  description = "Source (eastus2) fabric name."
  value       = azurerm_site_recovery_fabric.source.name
}

output "source_container_name" {
  description = "Source protection container name."
  value       = azurerm_site_recovery_protection_container.source.name
}

output "target_container_id" {
  description = "Target protection container ID."
  value       = azurerm_site_recovery_protection_container.target.id
}

output "policy_id" {
  description = "Replication policy ID (one day of recovery points, no app-consistent points)."
  value       = azurerm_site_recovery_replication_policy.one_day.id
}

output "target_network_id" {
  description = "VNet where failed-over VMs land."
  value       = module.network_dr.vnet_id
}

output "test_network_id" {
  description = "Isolated VNet where test-failover VMs land."
  value       = module.network_drtest.vnet_id
}

output "cache_account_id" {
  description = "ASR cache (staging) storage account ID, used as staging_storage_account_id on each replicated disk."
  value       = azurerm_storage_account.cache.id
}
