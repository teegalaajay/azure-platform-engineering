variable "monthly_budget_usd" {
  description = "Monthly cost budget for the subscription, in USD"
  type        = number

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be greater than 0."
  }
}

variable "budget_start_date" {
  description = "First day of the first budget month, RFC 3339 UTC (Azure requires the 1st of a month)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-01T00:00:00Z$", var.budget_start_date))
    error_message = "budget_start_date must be the first day of a month, like 2026-10-01T00:00:00Z."
  }
}

variable "alert_thresholds" {
  description = "Percent-of-budget thresholds; each one alerts on Actual and on Forecasted spend"
  type        = list(number)

  validation {
    condition     = length(var.alert_thresholds) > 0 && alltrue([for t in var.alert_thresholds : t > 0 && t <= 1000])
    error_message = "alert_thresholds must be a non-empty list of percentages between 0 and 1000."
  }
}

variable "budget_contact_emails" {
  description = "Alert recipients. Set via TF_VAR_budget_contact_emails (JSON list); never committed (public repo, ADR-0011)."
  type        = list(string)
  sensitive   = true # redacted in plan/apply output (plans are pasted into public PRs); still stored in state

  validation {
    condition     = length(var.budget_contact_emails) > 0 && alltrue([for e in var.budget_contact_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "budget_contact_emails must be a non-empty list of email addresses."
  }
}
