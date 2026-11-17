# DR networks (ADR-0007 amendment). Neither is peered: a failed-over or test VM has no path to hub, dev or prod.
module "network_dr" {
  source = "../../modules/network"

  name                = "vnet-dr-dev"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = var.dr_address_space
  tags                = local.tags

  subnets = {
    app = {
      address_prefix = cidrsubnet(var.dr_address_space[0], 8, 1) # 10.40.1.0/24
    }
  }
}

# Test failover target: ASR places test VMs in the subnet named in failover_test_subnet_name.
module "network_drtest" {
  source = "../../modules/network"

  name                = "vnet-drtest-dev"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = var.drtest_address_space
  tags                = local.tags

  subnets = {
    app = {
      address_prefix = cidrsubnet(var.drtest_address_space[0], 8, 1) # 10.41.1.0/24
    }
  }
}
