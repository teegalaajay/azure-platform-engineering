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

# Not in modules/network: the module names subnets "snet-<key>" and attaches an NSG to each.
# Azure requires this exact name, and (read, to be confirmed) allows no NSG on it.
# default_outbound_access_enabled is left at the provider default: whether a firewall subnet accepts
# false was not read before this change; exception to the ADR-0007 egress line, recorded in ADR-0039.
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = module.network.vnet_name # reference = VNet first
  address_prefixes     = [var.firewall_subnet_prefix]
}

# DNS Private Resolver subnets (ADR-0042). Standalone like the firewall subnet: modules/network has no
# delegation option and attaches an NSG to every subnet. Each endpoint needs its own dedicated subnet
# delegated to Microsoft.Network/dnsResolvers (read from Microsoft's Terraform example).
# No NSG yet: whether these subnets accept one was not read; exception recorded in ADR-0042.
resource "azurerm_subnet" "dns_inbound" {
  name                 = "snet-dns-in"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = module.network.vnet_name
  address_prefixes     = [var.dns_inbound_subnet_prefix]

  delegation {
    name = "Microsoft.Network.dnsResolvers"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "dns_outbound" {
  name                 = "snet-dns-out"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = module.network.vnet_name
  address_prefixes     = [var.dns_outbound_subnet_prefix]

  delegation {
    name = "Microsoft.Network.dnsResolvers"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}
