variable "name" {
  description = "Storage account name. Globally unique, 3-24 chars, lowercase letters and digits only"
  type        = string


  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name)) # regex() errors on no match; can() turns that error into false
    error_message = "name must be 3-24 characters, lowercase letters and digits only (Azure storage account rule)."
  }
}

variable "resource_group_name" {
  description = "Existing resource group the account is created in. The caller owns the RG."
  type        = string # no default: the module never decides where it lands
}

variable "location" {
  description = "Azure region, e.g. eastus2."
  type        = string
}

variable "replication_type" {
  description = "Redundancy: LRS, ZRS, GRS or GZRS"
  type        = string # no default: the caller must make the redundancy decision explicitly

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS"], var.replication_type)
    error_message = "replication_type must be one of LRS, ZRS, GRS, GZRS."
  }
}

variable "tags" {
  description = "Tags applied to the account"
  type        = map(string)

  validation {
    condition = alltrue([
      for k in ["owner", "environment", "cost_center", "data_classification", "managed_by", "repo"] :
      # Present AND non-null AND non-blank. A missing key (invalid index) or a null
      # (trimspace(null) errors) both raise an error, which try() turns into false.
      try(trimspace(var.tags[k]) != "", false)
    ])
    error_message = "tags must include non-empty values for owner, environment, cost_center, data_classification, managed_by and repo."
  }
}

variable "virtual_network_subnet_ids" {
  description = "Allow-list of source subnet IDs for the storage firewall (default action is always Deny). Each subnet must have the Microsoft.Storage service endpoint."
  type        = list(string) # no default: every caller decides its network paths explicitly

  validation {
    condition = alltrue([
      for id in var.virtual_network_subnet_ids :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", id))
    ])
    error_message = "Each virtual_network_subnet_ids entry must be a full Azure subnet resource ID."
  }

  # Cross-variable check (Terraform >= 1.9). With Deny hardcoded, two empty lists = an account nobody can reach.
  validation {
    condition     = length(var.virtual_network_subnet_ids) + length(var.ip_rules) > 0
    error_message = "Provide at least one allowed path: a subnet ID or a public IP."
  }
}

variable "ip_rules" {
  description = "Allow-list of public IPv4 addresses or CIDR ranges for the storage firewall. Single hosts as a bare IP (no /31 or /32). Private ranges are rejected."
  type        = list(string) # no default: see above

  validation {
    # Positive format check: IPv4 address, optional /prefix. Rejects "", whitespace, hostnames, truncated IPs.
    condition     = alltrue([for ip in var.ip_rules : can(regex("^(\\d{1,3}\\.){3}\\d{1,3}(/\\d{1,2})?$", ip))])
    error_message = "Each ip_rules entry must be an IPv4 address or CIDR, e.g. 203.0.113.10 or 203.0.113.0/24."
  }

  validation {
    condition = alltrue([
      for ip in var.ip_rules : !can(regex("(^10\\.)|(^172\\.(1[6-9]|2[0-9]|3[0-1])\\.)|(^192\\.168\\.)", ip))
    ])
    error_message = "ip_rules must not contain private (RFC 1918) addresses; VNet traffic is matched by virtual_network_subnet_ids instead."
  }

  validation {
    condition     = alltrue([for ip in var.ip_rules : !can(regex("/3[12]$", ip))])
    error_message = "ip_rules entries must not use /31 or /32; give a single host as a bare IP (e.g. 203.0.113.10)."
  }
}
