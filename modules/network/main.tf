resource "azurerm_virtual_network" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
  tags                = var.tags
}

# Standalone subnets (never inline subnet blocks in the VNet): each has its own address and
# lifecycle, so NSG changes never replace a subnet (ADR-0007).

resource "azurerm_subnet" "this" {
  for_each = var.subnets # key = app/data/mgmt -> address azurerm_subnet.this["app"]

  name                 = "snet-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name # reference = implicit dependency: VNet first
  address_prefixes     = [each.value.address_prefix]
  service_endpoints    = each.value.service_endpoints # [] when the caller omits it (optional default)
}
