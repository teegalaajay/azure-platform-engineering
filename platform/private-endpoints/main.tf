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

  # Fixed Azure names of the privatelink zone for each service; platform/dns owns the zones (ADR-0042).
  zone_names = {
    vault = "privatelink.vaultcore.azure.net"
    blob  = "privatelink.blob.core.windows.net"
  }
}

# Read, never managed here: other roots own all of these (ADR-0007, ADR-0010, ADR-0042, bootstrap script).
data "azurerm_subnet" "pe" {
  name                 = "snet-pe"
  virtual_network_name = var.hub_vnet_name
  resource_group_name  = var.hub_resource_group_name
}

data "azurerm_private_dns_zone" "this" {
  for_each = local.zone_names

  name                = each.value
  resource_group_name = var.dns_resource_group_name
}

data "azurerm_key_vault" "platform" {
  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group_name
}

data "azurerm_storage_account" "state" {
  name                = var.state_account_name
  resource_group_name = var.state_resource_group_name
}

resource "azurerm_resource_group" "this" {
  name     = "rg-private-endpoints-${var.environment}"
  location = var.location
  tags     = local.tags
}

locals {
  # One entry per endpoint: the target resource, its sub-resource (group id) and the zone that holds its record.
  endpoints = {
    vault = {
      name        = "pe-${var.key_vault_name}"
      resource_id = data.azurerm_key_vault.platform.id
      subresource = "vault"
      zone        = "vault"
    }
    state_blob = {
      name        = "pe-${var.state_account_name}-blob"
      resource_id = data.azurerm_storage_account.state.id
      subresource = "blob"
      zone        = "blob"
    }
  }
}

resource "azurerm_private_endpoint" "this" {
  for_each = local.endpoints

  name                = each.value.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = data.azurerm_subnet.pe.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${each.value.subresource}"
    private_connection_resource_id = each.value.resource_id
    subresource_names              = [each.value.subresource]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdzg-${each.value.zone}"
    private_dns_zone_ids = [data.azurerm_private_dns_zone.this[each.value.zone].id]
  }
}
