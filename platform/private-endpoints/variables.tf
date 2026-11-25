variable "location" {
  description = "Azure region; private endpoints must be in the same region as the VNet they attach to"
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
  description = "Hub VNet that holds snet-pe (platform/foundation/hub)"
  type        = string
}

variable "hub_resource_group_name" {
  description = "Resource group of the hub VNet"
  type        = string
}

variable "dns_resource_group_name" {
  description = "Resource group of the privatelink zones (platform/dns)"
  type        = string
}

variable "key_vault_name" {
  description = "Platform Key Vault that gets a private endpoint (platform/security)"
  type        = string
}

variable "key_vault_resource_group_name" {
  description = "Resource group of the platform Key Vault"
  type        = string
}

variable "state_account_name" {
  description = "Terraform state storage account that gets a private endpoint (bootstrap/state-backend.sh)"
  type        = string
}

variable "state_resource_group_name" {
  description = "Resource group of the state storage account"
  type        = string
}
