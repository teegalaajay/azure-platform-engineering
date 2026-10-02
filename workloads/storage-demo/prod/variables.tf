variable "environment" {
  description = "Environment name; drives the RG name and the environment tag"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "location" {
  description = "Azure region for the resource group and the storage account"
  type        = string
}

variable "data_classification" {
  description = "Data classification tag (engineering_standards §8)"
  type        = string

  validation {
    condition     = contains(["internal", "confidential", "gxp-regulated"], var.data_classification)
    error_message = "data_classification must be internal, confidential or gxp-regulated."
  }
}

variable "storage_account_name" {
  description = "Globally unique storage account name (validated by the module)"
  type        = string
}

variable "replication_type" {
  description = "Storage redundancy; an explicit per-environment decision (ADR-0006)"
  type        = string
}
