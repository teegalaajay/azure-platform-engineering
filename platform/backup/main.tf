locals {
  common_tags = {
    owner       = "platform-team"
    cost_center = "cc-platform-001"
    managed_by  = "terraform"
    repo        = "azure-platform-engineering"
  }

  tags = merge(local.common_tags, {
    environment         = "shared" # one vault serves all environments
    data_classification = var.data_classification
  })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-backup-shared"
  location = var.location
  tags     = local.tags
}

# Backup vault (ADR-0045). Holds recovery points; the ASR vault is a separate root in centralus.
resource "azurerm_recovery_services_vault" "this" {
  name                = var.vault_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  sku = "Standard" # the only SKU for a Recovery Services vault

  # Fixed once the first item is protected (validated in variables.tf).
  storage_mode_type = var.storage_mode_type

  # Restore into the paired region; needs GeoRedundant. Cannot be turned off after protection starts.
  cross_region_restore_enabled = true

  # Disabled or Unlocked only (Locked is refused in variables.tf).
  immutability = var.immutability

  # Cross Region Restore is not supported with public access Deny (read, ADR-0045).
  public_network_access_enabled = true

  lifecycle {
    prevent_destroy = true # plan-time guard: recovery points are not removed by a stray destroy
  }

  tags = local.tags
}

# ARM-side guard against deletes from any client.
resource "azurerm_management_lock" "vault_cannot_delete" {
  name       = "lock-cannotdelete-${azurerm_recovery_services_vault.this.name}"
  scope      = azurerm_recovery_services_vault.this.id
  lock_level = "CanNotDelete"
  notes      = "Platform backup vault: remove only via reviewed PR (ADR-0045)"

  lifecycle {
    prevent_destroy = true # removing the lock must be a deliberate two-step change
  }
}
