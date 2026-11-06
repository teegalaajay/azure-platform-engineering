variable "location" {
  description = "Azure region for the registry resource group and the registry"
  type        = string
}

variable "registry_name" {
  description = "Globally unique registry name; becomes <name>.azurecr.io (ADR-0036)."
  type        = string

  validation {
    # Azure: 5-50 alphanumeric characters, no hyphens. Lowercase enforced here by our naming standard.
    condition     = can(regex("^[a-z0-9]{5,50}$", var.registry_name))
    error_message = "registry_name must be 5-50 lowercase letters or digits (no hyphens)."
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
