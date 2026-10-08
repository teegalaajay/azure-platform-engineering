locals {
  # One notification per threshold x spend type: "actual_50", "forecasted_80", ...
  notifications = {
    for pair in setproduct(var.alert_thresholds, ["Actual", "Forecasted"]) :
    "${lower(pair[1])}_${pair[0]}" => {
      threshold      = pair[0]
      threshold_type = pair[1]
    }
  }
}

# Subscription ID is read from the provider's own context, so it never appears in the repo.
data "azurerm_subscription" "current" {}

# A budget alerts, it does not stop spend. It lives at subscription scope: no resource group,
# and the resource supports no tags (so the mandatory-tag rule has nothing to attach to; ADR-0011).
resource "azurerm_consumption_budget_subscription" "this" {
  name            = "budget-platform-shared-monthly"
  subscription_id = data.azurerm_subscription.current.id
  amount          = var.monthly_budget_usd
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  dynamic "notification" {
    for_each = local.notifications
    content {
      enabled        = true
      operator       = "GreaterThan"
      threshold      = notification.value.threshold
      threshold_type = notification.value.threshold_type
      contact_emails = var.budget_contact_emails
    }
  }
}
