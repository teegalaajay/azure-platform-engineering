
locals {
  # Org-wide mandatory tags (engineering_standards §8). Identical in every environment.
  common_tags = {
    owner       = "platform-team"
    cost_center = "cc-platform-001"
    managed_by  = "terraform"
    repo        = "azure-platform-engineering"
  }

  # Environment-specific tags go last so they win on any duplicate key.
  tags = merge(local.common_tags, {
    environment         = "prod"
    data_classification = "gxp-regulated"
  })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-storage-demo-prod"
  location = "eastus2"
  tags     = local.tags
}

module "storage" {
  source = "../../../modules/storage"

  name                = "stdemoprodat01"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  replication_type    = "GRS"
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
