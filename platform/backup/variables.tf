variable "location" {
  description = "Azure region of the Backup vault. Backup data lives here; the ASR vault is a separate root in the paired region."
  type        = string
}

variable "vault_name" {
  description = "Recovery Services vault name for backup (ADR-0045)."
  type        = string

  validation {
    # Azure: 2-50 chars, letters, digits, hyphens, starting with a letter and ending with a letter or digit.
    # Lowercase enforced by our naming standard, not by Azure.
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

variable "storage_mode_type" {
  description = "Vault storage redundancy. Must be set before the first item is protected; it cannot be changed afterwards (ADR-0045)."
  type        = string

  validation {
    # Cross Region Restore needs GRS; LRS and ZRS would silently remove the cross-region proof.
    condition     = var.storage_mode_type == "GeoRedundant"
    error_message = "storage_mode_type must be GeoRedundant: Cross Region Restore requires it and redundancy is fixed once protection starts."
  }
}

variable "immutability" {
  description = "Vault immutability state. Locked is irreversible and is refused here (ADR-0045)."
  type        = string

  validation {
    condition     = contains(["Disabled", "Unlocked"], var.immutability)
    error_message = "immutability must be Disabled or Unlocked. Locked cannot be reverted: change this validation in its own reviewed PR, with an ADR amendment, before ever setting it."
  }
}
