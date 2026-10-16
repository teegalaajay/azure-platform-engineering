locals {
  common_tags = {
    owner       = "platform-team"
    cost_center = "cc-platform-001"
    managed_by  = "terraform"
    repo        = "azure-platform-engineering"
  }

  # Environment-specific tags go last so they win on any duplicate key.
  tags = merge(local.common_tags, {
    environment         = var.environment
    data_classification = var.data_classification
  })
}

# Reads the hub root's OUTPUTS from its state blob (data-plane read: needs a blob data role).
data "terraform_remote_state" "hub" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stattfstate01"
    container_name       = "tfstate"
    key                  = "platform/foundation/hub.tfstate"
    use_azuread_auth     = true
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-runner-${var.environment}"
  location = var.location
  tags     = local.tags
}

module "runner" {
  source = "../../modules/runner-vm"

  name                = "vm-runner-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = data.terraform_remote_state.hub.outputs.mgmt_subnet_id
  size                = var.vm_size
  zone                = var.vm_zone
  private_ip_address  = var.private_ip_address
  ssh_public_key      = var.ssh_public_key
  tags                = local.tags

  repo_url           = var.repo_url
  registration_token = var.registration_token
  runner_version     = var.runner_version
  runner_sha256      = var.runner_sha256
  terraform_version  = var.terraform_version
}

# Interim explicit egress (ADR-0007, ADR-0008): replaced by the Week 8 firewall + UDR.
# Lives in this root so the cost stops when the runner is destroyed.
resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-runner-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "this" {
  name                = "ng-runner-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku_name            = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# A separate resource: attaches the NAT Gateway to the hub's snet-mgmt by ID.
resource "azurerm_subnet_nat_gateway_association" "this" {
  subnet_id      = data.terraform_remote_state.hub.outputs.mgmt_subnet_id
  nat_gateway_id = azurerm_nat_gateway.this.id
}
