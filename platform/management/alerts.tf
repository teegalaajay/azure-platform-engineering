# Notification path and the daily cap alert (ADR-0044). Recipients come from a sensitive
# variable; only their number is revealed, so the addresses stay out of plans.
resource "azurerm_monitor_action_group" "platform" {
  name                = "ag-platform-shared"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = "platform"
  location            = "global"

  dynamic "email_receiver" {
    for_each = toset([for i in range(nonsensitive(length(var.alert_contact_emails))) : tostring(i)])

    content {
      name                    = "recipient-${email_receiver.value}"
      email_address           = var.alert_contact_emails[tonumber(email_receiver.value)]
      use_common_alert_schema = true
    }
  }

  tags = local.tags
}

# Fires after collection has stopped (the cap event is written when the limit is hit), so it
# reports the loss, it cannot prevent it. Query and thresholds follow the Azure Monitor
# documentation for the daily cap.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "daily_cap_reached" {
  name                = "alert-law-daily-cap-reached"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  display_name         = "Platform workspace daily cap reached"
  description          = "Data collection in the platform workspace stopped because the daily cap was reached."
  severity             = 2 # warning
  enabled              = true
  scopes               = [azurerm_log_analytics_workspace.this.id]
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"

  criteria {
    query                   = <<-QUERY
      _LogOperation
      | where Category =~ "Ingestion"
      | where Detail contains "OverQuota"
    QUERY
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0
  }

  action {
    action_groups = [azurerm_monitor_action_group.platform.id]
  }

  tags = local.tags
}
