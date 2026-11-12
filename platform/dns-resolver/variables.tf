variable "location" {
  description = "Azure region; the resolver must be in the same region as the hub VNet"
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
  description = "Hub VNet that holds snet-dns-in and snet-dns-out (platform/foundation/hub)"
  type        = string
}

variable "hub_resource_group_name" {
  description = "Resource group of the hub VNet"
  type        = string
}

variable "dev_vnet_name" {
  description = "Dev spoke VNet linked to the forwarding ruleset (platform/foundation/dev)"
  type        = string
}

variable "dev_resource_group_name" {
  description = "Resource group of the dev spoke VNet"
  type        = string
}
