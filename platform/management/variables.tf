variable "location" {
  description = "Azure region for the management resource group and the workspace"
  type        = string
}

variable "workspace_name" {
  description = "Log Analytics workspace name, unique within the resource group (ADR-0044)."
  type        = string

  validation {
    # Azure: 4-63 chars, letters, digits and hyphens, start and end with a letter or digit.
    # Lowercase enforced here by our naming standard, not by Azure.
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,61}[a-z0-9]$", var.workspace_name))
    error_message = "workspace_name must be 4-63 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
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

variable "daily_quota_gb" {
  description = "Daily ingestion cap in GB. Collection stops for the rest of the day when it is reached (ADR-0044)."
  type        = number

  validation {
    # -1 means unlimited in the provider; refuse it so a typo cannot remove the cap.
    condition     = var.daily_quota_gb > 0
    error_message = "daily_quota_gb must be greater than 0; unlimited (-1) is not allowed here."
  }
}

variable "retention_in_days" {
  description = "Interactive retention in days (ADR-0044)."
  type        = number

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "retention_in_days must be between 30 and 730."
  }
}
