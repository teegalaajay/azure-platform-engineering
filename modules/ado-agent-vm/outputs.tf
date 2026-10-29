output "vm_id" {
  description = "VM resource ID"
  value       = module.vm.vm_id
}

output "private_ip_address" {
  description = "Private IP of the agent VM (the only address it has)"
  value       = module.vm.private_ip_address
}
