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
    environment         = "dev"
    data_classification = "internal" # dev holds no regulated data
  })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-storage-demo-dev"
  location = "eastus2"
  tags     = local.tags
}

module "storage" {
  source = "../../../modules/storage"

  name                = "stdemodevat01"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  replication_type    = "LRS"
  tags                = local.tags
}
