variable "location" {
  description = "Azure region for the security resource group and the vault"
  type        = string
}

variable "key_vault_name" {
  description = "Globally unique Key Vault name. Reserved for the soft-delete period after deletion (ADR-0010)."
  type        = string

  validation {
    # Azure: 3-24 chars, starts with a letter, ends with a letter or digit, no "--".
    # Lowercase enforced here by our naming standard, not by Azure.
    condition     = can(regex("^[a-z][a-z0-9-]{1,22}[a-z0-9]$", var.key_vault_name)) && !strcontains(var.key_vault_name, "--")
    error_message = "key_vault_name must be 3-24 lowercase letters, digits or single hyphens, start with a letter and end with a letter or digit."
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

variable "operator_ip_cidr" {
  description = "Operator public IP as /32. Set via TF_VAR_operator_ip_cidr; never committed (public repo)."
  type        = string
  sensitive   = true # redacted in plan/apply output; still stored in state (ADR-0002)

  validation {
    condition     = can(cidrhost(var.operator_ip_cidr, 0)) && endswith(var.operator_ip_cidr, "/32")
    error_message = "operator_ip_cidr must be a single IPv4 address in CIDR form ending in /32."
  }
}

variable "operator_object_id" {
  description = "Entra object ID of the human operator granted Key Vault Secrets Officer. Set via TF_VAR_operator_object_id; kept out of the public repo."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.operator_object_id))
    error_message = "operator_object_id must be a lowercase GUID."
  }
}
