variable "name" {
  description = "VNet name, e.g. vnet-spoke-prod"
  type        = string

  validation {
    condition     = can(regex("^vnet-[a-z0-9-]+$", var.name))
    error_message = "name must start with vnet- and use lowercase letters, digits and hyphens."
  }
}

variable "resource_group_name" {
  description = "Existing resource group for the VNet and its NSGs. The caller owns the RG."
  type        = string
}

variable "location" {
  description = "Azure region, e.g. eastus2"
  type        = string
}

variable "address_space" {
  description = "VNet CIDR blocks (ADR-0007 address plan)"
  type        = list(string)

  validation {
    condition     = length(var.address_space) > 0 && alltrue([for c in var.address_space : can(cidrhost(c, 0))])
    error_message = "address_space must contain at least one valid CIDR."
  }
}

variable "subnets" {
  description = "Subnets keyed by short name (app, data, mgmt). Key -> subnet snet-<key> and NSG nsg-<key>-<vnet suffix>."
  type = map(object({
    address_prefix    = string
    service_endpoints = optional(list(string), [])
    inbound_rules = optional(list(object({
      name                  = string
      priority              = number
      source_address_prefix = string
      port                  = string
      protocol              = optional(string, "Tcp")
    })), [])
  }))

  validation {
    condition     = alltrue([for k, s in var.subnets : can(cidrhost(s.address_prefix, 0))])
    error_message = "Every subnet address_prefix must be a valid CIDR."
  }

  validation {
    # 4000+ is reserved for the module's hardcoded deny-vnet-inbound rule
    condition     = alltrue(flatten([for k, s in var.subnets : [for r in s.inbound_rules : r.priority >= 100 && r.priority < 4000]]))
    error_message = "inbound_rules priorities must be 100-3999 (4000 and above are reserved by the module)."
  }
}

variable "tags" {
  description = "Tags applied to every resource the module creates"
  type        = map(string)

  validation {
    condition = alltrue([
      for k in ["owner", "environment", "cost_center", "data_classification", "managed_by", "repo"] :
      try(trimspace(var.tags[k]) != "", false)
    ])
    error_message = "tags must include non-empty values for owner, environment, cost_center, data_classification, managed_by and repo."
  }
}
