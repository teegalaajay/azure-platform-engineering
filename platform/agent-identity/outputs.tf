output "identity_id" {
  description = "Resource ID of the user-assigned identity; the VM attaches to it"
  value       = azurerm_user_assigned_identity.agent.id
}

output "identity_client_id" {
  description = "Client ID (GUID) of the identity; cloud-init passes it to az login --identity"
  value       = azurerm_user_assigned_identity.agent.client_id
}

output "identity_principal_id" {
  description = "Object ID of the identity's service principal, for role assignments in other roots"
  value       = azurerm_user_assigned_identity.agent.principal_id
}
