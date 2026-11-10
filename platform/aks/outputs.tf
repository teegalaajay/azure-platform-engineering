output "resource_group_name" {
  description = "Resource group of the cluster resource"
  value       = azurerm_resource_group.this.name
}

output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.this.name
}

output "node_resource_group_name" {
  description = "Resource group AKS creates for the node scale sets, load balancer and egress IP (deleted with the cluster)"
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity federated credentials"
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}
