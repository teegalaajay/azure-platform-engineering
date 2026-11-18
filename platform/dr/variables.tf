variable "location" {
  description = "Azure region of the ASR vault. Must be the target (DR) region: Site Recovery requires the vault in the region replicated to."
  type        = string
}

variable "vault_name" {
  description = "Recovery Services vault name for Site Recovery (ADR-0045)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,48}[a-z0-9]$", var.vault_name))
    error_message = "vault_name must be 2-50 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "data_classification" {
  description = "Data classification tag (engineering_standards §8)"
  type        = string

  validation {
    condition     = contains(["internal", "confidential", "gxp-regulated"], var.data_classification)
    error_message = "data_classification must be internal, confidential or gxp-regulated."
  }
}

variable "dr_address_space" {
  description = "Address space of the DR VNet where failed-over VMs land (ADR-0007 amendment). Must not overlap 10.10/16, 10.11/16, 10.20/16, 10.30/16 or 10.244/16."
  type        = list(string)

  validation {
    condition     = length(var.dr_address_space) > 0 && alltrue([for c in var.dr_address_space : can(cidrhost(c, 0))])
    error_message = "dr_address_space must contain at least one valid CIDR."
  }
}

variable "drtest_address_space" {
  description = "Address space of the isolated test-failover VNet (ADR-0007 amendment). Same overlap rule as dr_address_space."
  type        = list(string)

  validation {
    condition     = length(var.drtest_address_space) > 0 && alltrue([for c in var.drtest_address_space : can(cidrhost(c, 0))])
    error_message = "drtest_address_space must contain at least one valid CIDR."
  }
}


variable "cache_account_name" {
  description = "ASR cache (staging) storage account name. Same region and subscription as the source VM, not the target (ADR-0045)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.cache_account_name))
    error_message = "cache_account_name must be 3-24 lowercase letters and digits."
  }
}

variable "cache_location" {
  description = "Region of the cache account: the source region, where the protected VM runs."
  type        = string
}

variable "source_resource_group_name" {
  description = "Resource group of the source VNet, read (never managed) to allow its app subnet on the cache account firewall."
  type        = string
}

variable "source_vnet_name" {
  description = "Source VNet whose snet-app is allowed on the cache account firewall."
  type        = string
}
