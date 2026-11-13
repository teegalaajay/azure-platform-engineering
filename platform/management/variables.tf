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

variable "alert_contact_emails" {
  description = "Alert recipients for the platform action group. Set via TF_VAR_alert_contact_emails (JSON list); never committed (public repo, ADR-0044)."
  type        = list(string)
  sensitive   = true # redacted in plan/apply output (plans are pasted into public PRs); still stored in state

  validation {
    condition     = length(var.alert_contact_emails) > 0 && alltrue([for e in var.alert_contact_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "alert_contact_emails must be a non-empty list of email addresses."
  }
}
