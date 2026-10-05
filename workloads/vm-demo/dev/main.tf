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

# Reads the foundation root's OUTPUTS from its state blob (data-plane read: needs a blob data role).
data "terraform_remote_state" "foundation" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stattfstate01"
    container_name       = "tfstate"
    key                  = "platform/foundation/${var.environment}.tfstate"
    use_azuread_auth     = true # without it the backend tries shared keys, which are disabled
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-vm-demo-${var.environment}"
  location = var.location
  tags     = local.tags
}

module "vm" {
  source = "../../../modules/linux-vm"

  name                = "vm-demo-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = data.terraform_remote_state.foundation.outputs.subnet_ids["app"]
  size                = var.vm_size
  zone                = var.vm_zone
  private_ip_address  = var.private_ip_address
  ssh_public_key      = var.ssh_public_key
  tags                = local.tags
}

# Interim explicit egress (ADR-0007): replaced by the Week 8 firewall + UDR.
# Lives in this root so the cost stops when the workload is destroyed.
resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-vm-demo-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "this" {
  name                = "ng-vm-demo-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku_name            = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# A separate resource: attaches the NAT Gateway to the foundation's snet-app by ID.
resource "azurerm_subnet_nat_gateway_association" "this" {
  subnet_id      = data.terraform_remote_state.foundation.outputs.subnet_ids["app"]
  nat_gateway_id = azurerm_nat_gateway.this.id
}
