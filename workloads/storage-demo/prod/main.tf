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

resource "azurerm_resource_group" "this" {
  name     = "rg-storage-demo-${var.environment}"
  location = var.location
  tags     = local.tags
}

module "storage" {
  source              = "../../../modules/storage"
  name                = var.storage_account_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  replication_type    = var.replication_type
  tags                = local.tags
  virtual_network_subnet_ids = [
    data.terraform_remote_state.foundation.outputs.subnet_ids["app"], # spoke snet-app (this env)
    data.terraform_remote_state.hub.outputs.mgmt_subnet_id,           # hub snet-mgmt (runner, ops)
  ]
  ip_rules = [split("/", var.operator_ip_cidr)[0]] # "x.x.x.x/32" -> "x.x.x.x"; module rejects /32
}


resource "azurerm_management_lock" "storage" {
  name       = "lock-cannotdelete-${module.storage.name}"
  scope      = module.storage.id
  lock_level = "CanNotDelete"
  notes      = "GxP data: deletion requires a reviewed PR removing this lock (ADR)."

  lifecycle {
    prevent_destroy = true
  }
}

# Allowed paths are read from their owners, never typed (ADR-0009). Data-plane reads: need a blob data role.
data "terraform_remote_state" "foundation" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stattfstate01"
    container_name       = "tfstate"
    key                  = "platform/foundation/${var.environment}.tfstate"
    use_azuread_auth     = true
  }
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
