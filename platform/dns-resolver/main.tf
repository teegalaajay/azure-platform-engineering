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

  # Simulated on-premises DNS (ADR-0042: range 10.30.0.0/16). Nothing listens there:
  # a query that reaches this rule is forwarded and gets no answer, which is the proof.
  onprem_domain     = "onprem.internal."
  onprem_dns_server = "10.30.0.53"
  inbound_static_ip = "10.20.4.4"
}

# Read, never managed here: the network roots own all of these (ADR-0007, ADR-0042).
data "azurerm_virtual_network" "hub" {
  name                = var.hub_vnet_name
  resource_group_name = var.hub_resource_group_name
}

data "azurerm_subnet" "dns_inbound" {
  name                 = "snet-dns-in"
  virtual_network_name = var.hub_vnet_name
  resource_group_name  = var.hub_resource_group_name
}

data "azurerm_subnet" "dns_outbound" {
  name                 = "snet-dns-out"
  virtual_network_name = var.hub_vnet_name
  resource_group_name  = var.hub_resource_group_name
}

data "azurerm_virtual_network" "dev" {
  name                = var.dev_vnet_name
  resource_group_name = var.dev_resource_group_name
}

resource "azurerm_resource_group" "this" {
  name     = "rg-dns-resolver-${var.environment}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_private_dns_resolver" "this" {
  name                = "dnspr-hub-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  virtual_network_id  = data.azurerm_virtual_network.hub.id
  tags                = local.tags
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "this" {
  name                    = "in-dnspr-hub-${var.environment}"
  private_dns_resolver_id = azurerm_private_dns_resolver.this.id
  location                = azurerm_private_dns_resolver.this.location
  tags                    = local.tags

  ip_configurations {
    subnet_id                    = data.azurerm_subnet.dns_inbound.id
    private_ip_allocation_method = "Static"
    private_ip_address           = local.inbound_static_ip
  }
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "this" {
  name                    = "out-dnspr-hub-${var.environment}"
  private_dns_resolver_id = azurerm_private_dns_resolver.this.id
  location                = azurerm_private_dns_resolver.this.location
  subnet_id               = data.azurerm_subnet.dns_outbound.id
  tags                    = local.tags
}

resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "this" {
  name                                       = "dnsfrs-hub-${var.environment}"
  resource_group_name                        = azurerm_resource_group.this.name
  location                                   = azurerm_resource_group.this.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.this.id]
  tags                                       = local.tags
}

resource "azurerm_private_dns_resolver_forwarding_rule" "onprem" {
  name                      = "rule-onprem-internal"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.this.id
  domain_name               = local.onprem_domain
  enabled                   = true

  target_dns_servers {
    ip_address = local.onprem_dns_server
    port       = 53
  }
}

# The ruleset acts only in VNets linked to it: hub (where on-prem queries arrive) and dev (test VM).
resource "azurerm_private_dns_resolver_virtual_network_link" "this" {
  for_each = {
    hub = data.azurerm_virtual_network.hub.id
    dev = data.azurerm_virtual_network.dev.id
  }

  name                      = "vnetlink-${each.key}"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.this.id
  virtual_network_id        = each.value
}
