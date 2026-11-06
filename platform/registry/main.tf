locals {
  common_tags = {
    owner       = "platform-team"
    cost_center = "cc-platform-001"
    managed_by  = "terraform"
    repo        = "azure-platform-engineering"
  }

  tags = merge(local.common_tags, {
    environment         = "shared" # one registry serves all environments
    data_classification = var.data_classification
  })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-registry-shared"
  location = var.location
  tags     = local.tags
}

resource "azurerm_container_registry" "this" {
  name                = var.registry_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  # ADR-0036: hardcoded, never variables (a -var must not be able to change these).
  sku                           = "Basic" # Premium only for IP rules / private endpoint (Week 10)
  admin_enabled                 = false   # no shared username/password; Entra tokens only
  public_network_access_enabled = true    # Basic has no network rules; accepted risk, exit in Week 10

  tags = local.tags
}
