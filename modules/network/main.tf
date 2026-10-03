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

locals {
  vnet_suffix = trimprefix(var.name, "vnet-") # vnet-spoke-prod -> spoke-prod
}

# One NSG per subnet. Rules are inline only: never add azurerm_network_security_rule
# resources for these NSGs (ADR-0007). Names never change; rules change in place.
resource "azurerm_network_security_group" "this" {
  for_each = var.subnets

  name                = "nsg-${each.key}-${local.vnet_suffix}" # e.g. nsg-app-spoke-prod
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  # Caller rules: one generated block per element of inbound_rules (none for mgmt)
  dynamic "security_rule" {
    for_each = each.value.inbound_rules

    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = security_rule.value.protocol
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefix      = security_rule.value.source_address_prefix
      destination_address_prefix = "*"
    }
  }

  # Baseline, not caller-controlled: VirtualNetwork includes every peered range,
  # so override the default AllowVnetInBound (65000).
  security_rule {
    name                       = "deny-vnet-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

# The subnet<->NSG link as its own resource: replacing an NSG never touches the subnet.
resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.subnets

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}
