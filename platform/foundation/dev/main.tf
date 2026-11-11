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

  hub_mgmt_prefix = one(data.azurerm_subnet.hub_mgmt.address_prefixes) # read from Azure, not copied
}

# Hub objects are read, never managed, by this root (ADR-0007: one root per network)
data "azurerm_virtual_network" "hub" {
  name                = var.hub_vnet_name
  resource_group_name = var.hub_resource_group_name
}

data "azurerm_subnet" "hub_mgmt" {
  name                 = "snet-mgmt"
  virtual_network_name = var.hub_vnet_name
  resource_group_name  = var.hub_resource_group_name
}

resource "azurerm_resource_group" "this" {
  name     = "rg-network-${var.environment}"
  location = var.location
  tags     = local.tags
}

module "network" {
  source = "../../../modules/network"

  name                = "vnet-spoke-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = var.address_space
  tags                = local.tags

  subnets = {
    app = {
      address_prefix    = var.app_subnet_prefix
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
      inbound_rules = [
        { name = "allow-ssh-operator", priority = 100, source_address_prefix = var.operator_ip_cidr, port = "22" },
        { name = "allow-ssh-mgmt", priority = 110, source_address_prefix = local.hub_mgmt_prefix, port = "22" },
        { name = "allow-http-operator", priority = 120, source_address_prefix = var.operator_ip_cidr, port = "80" },
      ]
    }
    data = {
      address_prefix    = var.data_subnet_prefix
      service_endpoints = ["Microsoft.Storage"]
      inbound_rules = [
        { name = "allow-ssh-mgmt", priority = 110, source_address_prefix = local.hub_mgmt_prefix, port = "22" },
      ]
    }
    # The module's deny-vnet-inbound (4000) blocks node-to-node traffic, so both ranges are allowed explicitly.
    # aks_pod_cidr is repeated in platform/aks (pod_cidr). If one changes and the other does not, cross-node
    # pod traffic breaks silently. Change both in the same PR.
    aks-nodes = {
      address_prefix    = var.aks_subnet_prefix
      service_endpoints = []
      inbound_rules = [
        { name = "allow-aks-nodes", priority = 200, source_address_prefix = var.aks_subnet_prefix, port = "*", protocol = "*" },
        { name = "allow-aks-pods", priority = 210, source_address_prefix = var.aks_pod_cidr, port = "*", protocol = "*" },
      ]
    }
  }
}

# Peering is directional: both sides must exist for traffic to flow.
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-${module.network.vnet_name}-to-${var.hub_vnet_name}"
  resource_group_name       = azurerm_resource_group.this.name
  virtual_network_name      = module.network.vnet_name
  remote_virtual_network_id = data.azurerm_virtual_network.hub.id
  allow_forwarded_traffic   = true # accept traffic the hub firewall forwards in (ADR-0039)
}

# Child of the HUB VNet, so it lives in the hub's RG (residual coupling, ADR-0007)
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-${var.hub_vnet_name}-to-${module.network.vnet_name}"
  resource_group_name       = var.hub_resource_group_name
  virtual_network_name      = var.hub_vnet_name
  remote_virtual_network_id = module.network.vnet_id
  allow_forwarded_traffic   = true # accept traffic the hub firewall forwards in (ADR-0039)
}
