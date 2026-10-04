variable "location" {
  description = "Azure region"
  type        = string
}

variable "environment" {
  description = "Environment name; also used in resource names"
  type        = string
}

variable "data_classification" {
  description = "data_classification tag value"
  type        = string
}

variable "address_space" {
  description = "Spoke VNet CIDR blocks (ADR-0007)"
  type        = list(string)
}

variable "app_subnet_prefix" {
  description = "snet-app CIDR"
  type        = string
}

variable "data_subnet_prefix" {
  description = "snet-data CIDR"
  type        = string
}

variable "hub_vnet_name" {
  description = "Hub VNet to peer with (created by platform/foundation/hub)"
  type        = string
}

variable "hub_resource_group_name" {
  description = "Resource group of the hub VNet"
  type        = string
}

variable "operator_ip_cidr" {
  description = "Operator public IP as /32. Set via TF_VAR_operator_ip_cidr; never committed (public repo)."
  type        = string
  sensitive   = true # redacted in plan/apply output; still stored in state (ADR-0002)

  validation {
    condition     = can(cidrhost(var.operator_ip_cidr, 0)) && endswith(var.operator_ip_cidr, "/32")
    error_message = "operator_ip_cidr must be a single IPv4 address in CIDR form ending in /32."
  }
}
