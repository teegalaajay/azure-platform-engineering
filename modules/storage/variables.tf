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
