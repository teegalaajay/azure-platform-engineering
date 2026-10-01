resource "azurerm_resource_group" "this" {
  name     = "rg-storage-demo-dev"
  location = "eastus2"
  tags = {
    owner               = "platform-team"
    environment         = "dev"
    cost_center         = "cc-platform-001"
    data_classification = "internal" # dev holds no regulated data
    managed_by          = "terraform"
    repo                = "azure-platform-engineering"
  }
}

module "storage" {
  source = "../../../modules/storage"

  name                = "stdemodevat01"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  replication_type    = "LRS"
  tags                = azurerm_resource_group.this.tags
}
