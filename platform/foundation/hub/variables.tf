variable "location" {
  description = "Azure region"
  type        = string
}

variable "environment" {
  description = "Environment tag value; the hub serves every environment"
  type        = string
}

variable "data_classification" {
  description = "data_classification tag value"
  type        = string
}

variable "address_space" {
  description = "Hub VNet CIDR blocks (ADR-0007)"
  type        = list(string)
}

variable "mgmt_subnet_prefix" {
  description = "snet-mgmt CIDR (CI runner / ADO agent)"
  type        = string
}
