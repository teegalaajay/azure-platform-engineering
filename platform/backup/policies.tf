# Standard tier: one backup a day (ADR-0045). V1 is the daily policy type.
resource "azurerm_backup_policy_vm" "standard" {
  name                = "bkp-vm-standard"
  resource_group_name = azurerm_resource_group.this.name
  recovery_vault_name = azurerm_recovery_services_vault.this.name

  policy_type = "V1"
  timezone    = "UTC"

  instant_restore_retention_days = 2

  backup {
    frequency = "Daily"
    time      = "02:00"
  }

  retention_daily {
    count = 30
  }

  retention_weekly {
    count    = 12
    weekdays = ["Sunday"]
  }

  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }
  lifecycle {
    prevent_destroy = true # a deleted policy would leave protected VMs without a schedule (ADR-0045)
  }
}

# Regulated tier: a backup every 4 hours, the shortest interval Azure supports for VMs (ADR-0045).
# V2 (the enhanced policy) is required for sub-daily backups.
resource "azurerm_backup_policy_vm" "regulated" {
  name                = "bkp-vm-regulated"
  resource_group_name = azurerm_resource_group.this.name
  recovery_vault_name = azurerm_recovery_services_vault.this.name

  policy_type = "V2"
  timezone    = "UTC"

  instant_restore_retention_days = 5

  backup {
    frequency     = "Hourly"
    time          = "02:00"
    hour_interval = 4
    hour_duration = 24
  }

  retention_daily {
    count = 35
  }

  retention_weekly {
    count    = 12
    weekdays = ["Sunday"]
  }

  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }
  lifecycle {
    prevent_destroy = true # a deleted policy would leave protected VMs without a schedule (ADR-0045)
  }
}
