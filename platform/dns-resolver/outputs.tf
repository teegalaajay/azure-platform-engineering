output "inbound_endpoint_ip" {
  description = "Inbound endpoint IP: the target of on-premises conditional forwarders"
  value       = azurerm_private_dns_resolver_inbound_endpoint.this.ip_configurations[0].private_ip_address
}

output "ruleset_id" {
  description = "Forwarding ruleset ID"
  value       = azurerm_private_dns_resolver_dns_forwarding_ruleset.this.id
}
