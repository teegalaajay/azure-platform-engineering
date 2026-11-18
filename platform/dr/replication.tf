# The source VNet is read, never managed, by this root (ADR-0007: one root per network).
data "azurerm_virtual_network" "source" {
  name                = var.source_vnet_name
  resource_group_name = var.source_resource_group_name
}

# One fabric per region: the source (where the VM runs) and the target (where replicas live).
resource "azurerm_site_recovery_fabric" "source" {
  name                = "fabric-${var.cache_location}"
  resource_group_name = azurerm_resource_group.this.name
  recovery_vault_name = azurerm_recovery_services_vault.this.name
  location            = var.cache_location
}

resource "azurerm_site_recovery_fabric" "target" {
  name                = "fabric-${azurerm_resource_group.this.location}"
  resource_group_name = azurerm_resource_group.this.name
  recovery_vault_name = azurerm_recovery_services_vault.this.name
  location            = azurerm_resource_group.this.location
}

resource "azurerm_site_recovery_protection_container" "source" {
  name                 = "container-${var.cache_location}"
  resource_group_name  = azurerm_resource_group.this.name
  recovery_vault_name  = azurerm_recovery_services_vault.this.name
  recovery_fabric_name = azurerm_site_recovery_fabric.source.name
}

resource "azurerm_site_recovery_protection_container" "target" {
  name                 = "container-${azurerm_resource_group.this.location}"
  resource_group_name  = azurerm_resource_group.this.name
  recovery_vault_name  = azurerm_recovery_services_vault.this.name
  recovery_fabric_name = azurerm_site_recovery_fabric.target.name
}

# ADR-0045 decision A.3: keep recovery points for one day, no app-consistent points.
# Both values are in minutes. 0 for "disabled" is unproven until the apply.
resource "azurerm_site_recovery_replication_policy" "one_day" {
  name                                                 = "asr-policy-1d"
  resource_group_name                                  = azurerm_resource_group.this.name
  recovery_vault_name                                  = azurerm_recovery_services_vault.this.name
  recovery_point_retention_in_minutes                  = 1440
  application_consistent_snapshot_frequency_in_minutes = 0
}

# Applies the policy to the source-to-target container pair.
resource "azurerm_site_recovery_protection_container_mapping" "this" {
  name                                      = "mapping-${var.cache_location}-to-${azurerm_resource_group.this.location}"
  resource_group_name                       = azurerm_resource_group.this.name
  recovery_vault_name                       = azurerm_recovery_services_vault.this.name
  recovery_fabric_name                      = azurerm_site_recovery_fabric.source.name
  recovery_replication_policy_id            = azurerm_site_recovery_replication_policy.one_day.id
  recovery_source_protection_container_name = azurerm_site_recovery_protection_container.source.name
  recovery_target_protection_container_id   = azurerm_site_recovery_protection_container.target.id
}

# Default failover landing network for VMs from the source VNet.
resource "azurerm_site_recovery_network_mapping" "this" {
  name                        = "netmap-${var.source_vnet_name}-to-${module.network_dr.vnet_name}"
  resource_group_name         = azurerm_resource_group.this.name
  recovery_vault_name         = azurerm_recovery_services_vault.this.name
  source_recovery_fabric_name = azurerm_site_recovery_fabric.source.name
  target_recovery_fabric_name = azurerm_site_recovery_fabric.target.name
  source_network_id           = data.azurerm_virtual_network.source.id
  target_network_id           = module.network_dr.vnet_id
}
