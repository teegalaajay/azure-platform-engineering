variable "location" {
  description = "Region of the resource group (the zones and links themselves are global)"
  type        = string
}

variable "environment" {
  description = "Environment tag value; shared for platform-wide components"
  type        = string
}

variable "data_classification" {
  description = "Data classification tag value"
  type        = string
}

variable "private_dns_zones" {
  description = "Private DNS zones to create, keyed by a short name. Each is the privatelink zone of one service (ADR-0042)."
  type        = map(string)

  validation {
    condition     = length(var.private_dns_zones) > 0 && alltrue([for z in values(var.private_dns_zones) : startswith(z, "privatelink.")])
    error_message = "private_dns_zones must be non-empty and every zone name must start with privatelink."
  }
}

variable "linked_vnets" {
  description = "VNets whose resolver uses the zones, keyed by a short name (ADR-0042)"
  type = map(object({
    name                = string
    resource_group_name = string
  }))

  validation {
    condition     = length(var.linked_vnets) > 0
    error_message = "linked_vnets must contain at least one VNet."
  }
}
