locals {
  common_tags = {
    owner       = "platform-team"
    cost_center = "cc-platform-001"
    managed_by  = "terraform"
    repo        = "azure-platform-engineering"
  }

  tags = merge(local.common_tags, {
    environment         = var.environment
    data_classification = var.data_classification
  })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-network-${var.environment}" # rg-network-shared
  location = var.location
  tags     = local.tags
}

module "network" {
  source = "../../../modules/network"

  name                = "vnet-hub-${var.environment}" # vnet-hub-shared
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = var.address_space
  tags                = local.tags

  subnets = {
    mgmt = {
      address_prefix    = var.mgmt_subnet_prefix
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
      # no inbound_rules: the runner only connects outbound (ADR-0007)
    }
  }
}
