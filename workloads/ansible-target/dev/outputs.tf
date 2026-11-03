output "resource_group_name" {
  description = "Resource group holding the Ansible target"
  value       = azurerm_resource_group.this.name
}

output "target_host" {
  description = "Private IP of the Ansible target; the Ansible stage reads this instead of a typed parameter (ADR-0030)"
  value       = module.vm.private_ip_address
}

output "target_user" {
  description = "Admin user the Ansible stage connects as; module default, repeated here so the pipeline does not hardcode it"
  value       = "azureuser"
}
