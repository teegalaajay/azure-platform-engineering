resource "azurerm_resource_group" "this" {
  name     = "rg-storage-demo-prod"
  location = "eastus2"
  tags = {
    owner               = "platform-team"
    environment         = "prod"
    cost_center         = "cc-platform-001"
    data_classification = "gxp-regulated"
    managed_by          = "terraform"
    repo                = "azure-platform-engineering"
  }
}

module "storage" {
  source = "../../../modules/storage"

  name                = "stdemoprodat01"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  replication_type    = "GRS"
  tags                = azurerm_resource_group.this.tags
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
