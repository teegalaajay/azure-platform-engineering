variable "location" {
  description = "Azure region for the firewall resources"
  type        = string
}

variable "environment" {
  description = "Environment token for names and tags (the hub is shared)"
  type        = string
}

variable "data_classification" {
  description = "Mandatory tag value"
  type        = string
}

variable "hub_vnet_name" {
  description = "Hub VNet that holds AzureFirewallSubnet (platform/foundation/hub)"
  type        = string
}

variable "hub_resource_group_name" {
  description = "Resource group of the hub VNet"
  type        = string
}

variable "dev_vnet_name" {
  description = "Dev spoke VNet whose snet-app is routed through the firewall (platform/foundation/dev)"
  type        = string
}

variable "dev_resource_group_name" {
  description = "Resource group of the dev spoke VNet"
  type        = string
}

variable "prod_vnet_name" {
  description = "Prod spoke VNet, read for its address space (platform/foundation/prod)"
  type        = string
}

variable "prod_resource_group_name" {
  description = "Resource group of the prod spoke VNet"
  type        = string
}
