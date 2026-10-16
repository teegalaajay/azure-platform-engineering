output "vm_id" {
  description = "Runner VM resource ID"
  value       = module.vm.vm_id
}

output "nic_id" {
  description = "Runner NIC resource ID"
  value       = module.vm.nic_id
}

output "private_ip_address" {
  description = "Private IP of the runner (its only address)"
  value       = module.vm.private_ip_address
}
