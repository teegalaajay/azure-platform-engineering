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

  # The only disk in the source group is the VM's OS disk; the precondition below enforces that.
  os_disk = one(data.azurerm_managed_disks.source.disk)
}

# Reads the DR root's OUTPUTS from its state blob (data-plane read: needs a blob data role).
data "terraform_remote_state" "dr" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stattfstate01"
    container_name       = "tfstate"
    key                  = "platform/dr.tfstate"
    use_azuread_auth     = true # without it the backend tries shared keys, which are disabled
  }
}

data "azurerm_virtual_machine" "source" {
  name                = var.source_vm_name
  resource_group_name = var.source_vm_resource_group_name
}

data "azurerm_network_interface" "source" {
  name                = "nic-${var.source_vm_name}"
  resource_group_name = var.source_vm_resource_group_name
}

data "azurerm_managed_disks" "source" {
  resource_group_name = var.source_vm_resource_group_name
}

# Receives the failed-over VM and its disks in the target region. Ephemeral with the replication.
resource "azurerm_resource_group" "target" {
  name     = var.target_resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_site_recovery_replicated_vm" "this" {
  name                = "repl-${var.source_vm_name}"
  resource_group_name = data.terraform_remote_state.dr.outputs.resource_group_name
  recovery_vault_name = data.terraform_remote_state.dr.outputs.vault_name

  source_vm_id                              = data.azurerm_virtual_machine.source.id
  source_recovery_fabric_name               = data.terraform_remote_state.dr.outputs.source_fabric_name
  source_recovery_protection_container_name = data.terraform_remote_state.dr.outputs.source_container_name
  recovery_replication_policy_id            = data.terraform_remote_state.dr.outputs.policy_id

  target_resource_group_id                = azurerm_resource_group.target.id
  target_recovery_fabric_id               = data.terraform_remote_state.dr.outputs.target_fabric_id
  target_recovery_protection_container_id = data.terraform_remote_state.dr.outputs.target_container_id
  target_network_id                       = data.terraform_remote_state.dr.outputs.target_network_id
  test_network_id                         = data.terraform_remote_state.dr.outputs.test_network_id
  target_zone                             = var.target_zone

  managed_disk = [
    {
      disk_id                       = local.os_disk.id
      staging_storage_account_id    = data.terraform_remote_state.dr.outputs.cache_account_id
      target_resource_group_id      = azurerm_resource_group.target.id
      target_disk_type              = local.os_disk.storage_account_type
      target_replica_disk_type      = local.os_disk.storage_account_type
      target_disk_encryption_set_id = null
      target_disk_encryption        = null
    }
  ]

  network_interface = [
    {
      source_network_interface_id                     = data.azurerm_network_interface.source.id
      target_subnet_name                              = var.target_subnet_name
      failover_test_subnet_name                       = var.test_subnet_name
      target_static_ip                                = null
      failover_test_static_ip                         = null
      recovery_public_ip_address_id                   = null
      failover_test_public_ip_address_id              = null
      recovery_load_balancer_backend_address_pool_ids = null
    }
  ]

  lifecycle {
    precondition {
      condition     = length(data.azurerm_managed_disks.source.disk) == 1
      error_message = "The source resource group must hold exactly one disk (the OS disk); detach or move any other disk first."
    }
  }
}
