locals {
  common_tags = {
    owner       = "platform-team"
    cost_center = "cc-platform-001"
    managed_by  = "terraform"
    repo        = "azure-platform-engineering"
  }

  # Environment-specific tags go last so they win on any duplicate key.
  tags = merge(local.common_tags, {
    environment         = var.environment
    data_classification = var.data_classification
  })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-storage-demo-${var.environment}"
  location = var.location
  tags     = local.tags
}

module "storage" {
  source = "../../../modules/storage"

  name                = var.storage_account_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  replication_type    = var.replication_type
  tags                = local.tags
}

resource "azurerm_management_lock" "storage" {
  name       = "lock-cannotdelete-${module.storage.name}"
  scope      = module.storage.id
  lock_level = "CanNotDelete"
  notes      = "GxP data: deletion requires a reviewed PR removing this lock (ADR)."

  lifecycle {
    prevent_destroy = true
  }
}
