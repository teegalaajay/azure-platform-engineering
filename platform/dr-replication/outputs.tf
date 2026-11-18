output "target_resource_group_name" {
  description = "Resource group in the target region that holds the replica disks and receives the failed-over VM"
  value       = azurerm_resource_group.target.name
}

output "replicated_vm_id" {
  description = "ID of the Site Recovery protected item for the replicated VM"
  value       = azurerm_site_recovery_replicated_vm.this.id
}
