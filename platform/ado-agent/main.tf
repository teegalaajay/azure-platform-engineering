# EPHEMERAL root, applied by hand and destroyed after each session. It owns the interim NAT Gateway
# on the hub's snet-mgmt, exactly like platform/runner (ADR-0007, ADR-0008). A subnet takes one NAT
# Gateway, so this root and platform/runner must never be applied at the same time.
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

data "terraform_remote_state" "security" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stattfstate01"
    container_name       = "tfstate"
    key                  = "platform/security.tfstate"
    use_azuread_auth     = true
  }
}

data "terraform_remote_state" "identity" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stattfstate01"
    container_name       = "tfstate"
    key                  = "platform/agent-identity.tfstate"
    use_azuread_auth     = true
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-ado-agent-${var.environment}"
  location = var.location
  tags     = local.tags
}

module "agent" {
  source = "../../modules/ado-agent-vm"

  name                = "vm-adoagent-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = data.terraform_remote_state.hub.outputs.mgmt_subnet_id
  size                = var.vm_size
  zone                = var.vm_zone
  private_ip_address  = var.private_ip_address
  ssh_public_key      = var.ssh_public_key
  tags                = local.tags

  user_assigned_identity_id = data.terraform_remote_state.identity.outputs.identity_id
  identity_client_id        = data.terraform_remote_state.identity.outputs.identity_client_id
  key_vault_name            = data.terraform_remote_state.security.outputs.key_vault_name
  agent_token_secret_name   = var.agent_token_secret_name
  ado_organization_url      = var.ado_organization_url
  agent_pool                = var.agent_pool
  agent_version             = var.agent_version
  agent_sha256              = var.agent_sha256
  terraform_version         = var.terraform_version
}

# Interim explicit egress (ADR-0007, ADR-0008): replaced by the Week 8 firewall + UDR.
resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-adoagent-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "this" {
  name                = "ng-adoagent-${var.environment}"
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
