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

# Read, never managed here: the network roots (ADR-0007) own all of these.
data "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  virtual_network_name = var.hub_vnet_name
  resource_group_name  = var.hub_resource_group_name
}

data "azurerm_virtual_network" "dev" {
  name                = var.dev_vnet_name
  resource_group_name = var.dev_resource_group_name
}

data "azurerm_subnet" "dev_app" {
  name                 = "snet-app"
  virtual_network_name = var.dev_vnet_name
  resource_group_name  = var.dev_resource_group_name
}

data "azurerm_virtual_network" "prod" {
  name                = var.prod_vnet_name
  resource_group_name = var.prod_resource_group_name
}

resource "azurerm_resource_group" "this" {
  name     = "rg-firewall-${var.environment}"
  location = var.location
  tags     = local.tags
}

# The policy owns threat intelligence and DNS settings, so the firewall resource sets neither.
# DNS proxy stays at its default (off): Week 9 decides the DNS path (ADR-0039).
resource "azurerm_firewall_policy" "this" {
  name                     = "fwp-hub-${var.environment}"
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  sku                      = "Standard"
  threat_intelligence_mode = "Deny"
  tags                     = local.tags
}

resource "azurerm_firewall_policy_rule_collection_group" "this" {
  name               = "rcg-hub-${var.environment}"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 100

  # Explicit deny dev -> prod on every port. Network rules are evaluated before application rules,
  # so this holds against any application allow; a later network allow with a lower number would
  # override it (ADR-0039).
  network_rule_collection {
    name     = "deny-dev-to-prod"
    priority = 100
    action   = "Deny"

    rule {
      name                  = "dev-to-prod"
      protocols             = ["Any"]
      source_addresses      = data.azurerm_virtual_network.dev.address_space
      destination_addresses = data.azurerm_virtual_network.prod.address_space
      destination_ports     = ["*"]
    }
  }

  # The one allowed destination: a public FQDN, over HTTPS only, from the dev app subnet only.
  application_rule_collection {
    name     = "allow-ipify"
    priority = 200
    action   = "Allow"

    rule {
      name              = "ipify"
      source_addresses  = data.azurerm_subnet.dev_app.address_prefixes
      destination_fqdns = ["api.ipify.org"]

      protocols {
        type = "Https"
        port = 443
      }
    }
  }
}

locals {
  # One list for both resources: a firewall and its public IP may not sit in different single zones.
  zones = ["1", "2", "3"]
}

resource "azurerm_public_ip" "firewall" {
  name                = "pip-fw-hub-${var.environment}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = local.zones
  tags                = local.tags
}

resource "azurerm_firewall" "this" {
  name     = "fw-hub-${var.environment}"
  location = azurerm_resource_group.this.location
  # Azure requires the firewall to sit in the resource group of the VNet it uses (AzureFirewallReferencesSubnetInDifferentResourceGroup, observed 2026-11-11).
  resource_group_name = var.hub_resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.this.id
  zones               = local.zones

  ip_configuration {
    name                 = "ipconfig-hub"
    subnet_id            = data.azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  # Precaution (reasoned, not reproduced): Azure serialises changes to a policy, so the rules are
  # written before the firewall attaches to it.
  depends_on = [azurerm_firewall_policy_rule_collection_group.this]

  tags = local.tags
}

# Lives in this root on purpose: destroying the firewall must also remove the route that points at it.
resource "azurerm_route_table" "dev_app" {
  name                = "rt-snet-app-dev"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  # Reasoned: with a gateway in the VNet, propagated routes could bypass the UDRs below. Dev has none today.
  bgp_route_propagation_enabled = false

  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.this.ip_configuration[0].private_ip_address
  }

  # Needed in addition to 0.0.0.0/0: the system route 10.0.0.0/8 -> None is longer than 0.0.0.0/0 and
  # would drop dev -> prod before it reaches the firewall. This /16 is longer than the /8 (ADR-0039).
  route {
    name                   = "prod-via-firewall"
    address_prefix         = data.azurerm_virtual_network.prod.address_space[0]
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.this.ip_configuration[0].private_ip_address
  }

  tags = local.tags
}

resource "azurerm_subnet_route_table_association" "dev_app" {
  subnet_id      = data.azurerm_subnet.dev_app.id
  route_table_id = azurerm_route_table.dev_app.id
}
