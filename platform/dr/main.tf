locals {
  common_tags = {
    owner       = "platform-team"
    cost_center = "cc-platform-001"
    managed_by  = "terraform"
    repo        = "azure-platform-engineering"
  }

  tags = merge(local.common_tags, {
    environment         = "shared" # one DR vault serves all environments
    data_classification = var.data_classification
  })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-dr-shared"
  location = var.location
  tags     = local.tags
}

# Site Recovery vault (ADR-0045). Lives in the target region; the backup vault is a separate root in eastus2.
resource "azurerm_recovery_services_vault" "this" {
  name                = var.vault_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  sku = "Standard" # the only SKU for a Recovery Services vault

  # The vault's own identity is granted access to the cache storage account,
  # so the cache account can keep shared key access off.
  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    prevent_destroy = true # plan-time guard
  }

  tags = local.tags
}

# ARM-side guard against deletes from any client.
resource "azurerm_management_lock" "vault_cannot_delete" {
  name       = "lock-cannotdelete-${azurerm_recovery_services_vault.this.name}"
  scope      = azurerm_recovery_services_vault.this.id
  lock_level = "CanNotDelete"
  notes      = "Platform DR vault: remove only via reviewed PR (ADR-0045)"

  lifecycle {
    prevent_destroy = true # removing the lock must be a deliberate two-step change
  }
}
