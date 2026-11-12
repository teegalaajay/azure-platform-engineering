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

  # Every zone linked to every VNet: 3 zones x 3 VNets = 9 links (ADR-0042).
  links = {
    for pair in setproduct(keys(var.private_dns_zones), keys(var.linked_vnets)) :
    "${pair[0]}_${pair[1]}" => { zone = pair[0], vnet = pair[1] }
  }
}

# Looked up by name, never typed as IDs (same pattern as the spoke roots reading the hub).
data "azurerm_virtual_network" "this" {
  for_each = var.linked_vnets

  name                = each.value.name
  resource_group_name = each.value.resource_group_name
}

resource "azurerm_resource_group" "this" {
  name     = "rg-dns-${var.environment}" # rg-dns-shared
  location = var.location
  tags     = local.tags
}

# Zones are global: location is not an argument. The record inside is written by each private
# endpoint's zone group, so there is no record resource here.
resource "azurerm_private_dns_zone" "this" {
  for_each = var.private_dns_zones

  name                = each.value
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.links

  name                  = "link-${var.linked_vnets[each.value.vnet].name}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.value.zone].name
  virtual_network_id    = data.azurerm_virtual_network.this[each.value.vnet].id

  registration_enabled = false              # auto-registration is for VM names, not privatelink zones
  resolution_policy    = "NxDomainRedirect" # ADR-0042: vendor accounts must stay reachable
  tags                 = local.tags
}
