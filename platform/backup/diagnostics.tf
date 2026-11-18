# Reads the management root's OUTPUTS from its state blob (data-plane read: needs a blob data role).
data "terraform_remote_state" "management" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stattfstate01"
    container_name       = "tfstate"
    key                  = "platform/management.tfstate"
    use_azuread_auth     = true # without it the backend tries shared keys, which are disabled
  }
}

locals {
  # Backup categories only. The Site Recovery categories belong to the DR vault (ADR-0045).
  backup_log_categories = [
    "CoreAzureBackup",
    "AddonAzureBackupJobs",
    "AddonAzureBackupAlerts",
    "AddonAzureBackupPolicy",
    "AddonAzureBackupStorage",
    "AddonAzureBackupProtectedInstance",
  ]
}

# Explicit setting instead of policy: one persistent vault, so a policy would add no coverage (ADR-0045).
resource "azurerm_monitor_diagnostic_setting" "vault_to_workspace" {
  name                       = "diag-vault-to-law"
  target_resource_id         = azurerm_recovery_services_vault.this.id
  log_analytics_workspace_id = data.terraform_remote_state.management.outputs.workspace_id

  # Resource-specific tables, as chosen for the workspace in ADR-0044.
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = toset(local.backup_log_categories)

    content {
      category = enabled_log.value
    }
  }
}
